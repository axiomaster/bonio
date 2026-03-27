#include "core/TaskExecutor.h"
#include "Config.h"
#include "ConfigManager.h"
#include "AppPackages.h"
#include <iostream>
#include <fstream>
#include <chrono>
#include <sstream>
#include <random>
#include <iomanip>
#include <ctime>
#include <nlohmann/json.hpp>
#include <regex>

using json = nlohmann::json;

// External global interruption flag (defined in main.cpp)
extern std::atomic<bool> g_interrupted;

TaskExecutor::TaskExecutor() {
}

TaskExecutor::TaskExecutor(std::unique_ptr<IPlatform> platform)
    : platform_(std::move(platform)) {
}

TaskExecutor::~TaskExecutor() {
}

bool TaskExecutor::initialize() {
    // Create platform if not injected
    if (!platform_) {
        platform_ = PlatformFactory::create();
        if (!platform_) {
            std::cerr << "Failed to create platform instance" << std::endl;
            return false;
        }
    }

    // Initialize screen size
    initScreenSize();

    // Load configuration
    Config::getInstance().loadFromFile();

    // Create HTTP client from platform
    http_client_ = std::unique_ptr<IHttpClient>(platform_->createHttpClient());
    if (!http_client_ || !http_client_->initialize()) {
        std::cerr << "Failed to initialize HTTP client" << std::endl;
        return false;
    }

    // Initialize GLM client
    glm_client_ = std::make_unique<AutoGLMClient>();
    if (!glm_client_->initialize()) {
        std::cerr << "Failed to initialize AutoGLM client" << std::endl;
        return false;
    }

    std::cout << "TaskExecutor initialized on " << platform_->getName() << std::endl;
    return true;
}

void TaskExecutor::initScreenSize() {
    if (!platform_->getScreenSize(screen_width_, screen_height_)) {
        // Fallback defaults
        screen_width_ = 1080;
        screen_height_ = 2400;
    }
    std::cout << "Screen size: " << screen_width_ << "x" << screen_height_ << std::endl;
}

bool TaskExecutor::captureScreenshot(std::string& out_path) {
    auto now = std::chrono::system_clock::now();
    auto timestamp = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << "/data/local/tmp/screenshot_" << timestamp << ".jpeg";
    out_path = ss.str();

    // Use 0.5x dimensions to reduce image size
    int half_w = screen_width_ / 2;
    int half_h = screen_height_ / 2;

    return platform_->takeScreenshot(out_path, half_w, half_h);
}

Task TaskExecutor::executeTask(const std::string& user_command,
                              const std::string& current_screenshot,
                              const std::string& ui_tree) {
    Task task;
    task.task_id = generateTaskId();
    task.user_command = user_command;
    task.status = TaskStatus::Pending;
    task.timestamp = getCurrentTimestamp();

    std::cout << "[" << task.task_id << "] Executing task: " << user_command << std::endl;

    // --- AGENT LOOP START ---

    // Maintain local conversation history for this task
    std::vector<json> conversation_history;

    // Add System Prompt
    conversation_history.push_back(AutoGLMClient::createSystemMessage(
        Config::getInstance().getSystemPrompt()
    ));

    // Initial User Prompt
    std::string initial_user_text = "Task: " + user_command;
    conversation_history.push_back(AutoGLMClient::createUserMessage(
        initial_user_text,
        ""
    ));

    // Loop control
    int step_limit = max_step_limit_;
    int step_count = 0;
    bool task_completed = false;
    std::string last_screenshot_path = current_screenshot;

    while (step_count < step_limit && !task_completed && !isInterrupted()) {
        if (isInterrupted()) {
            std::cout << "[" << task.task_id << "] Interrupted by user" << std::endl;
            task.status = TaskStatus::Interrupted;
            task.error_message = "Task interrupted by user (Ctrl+C)";
            break;
        }

        std::cout << "[" << task.task_id << "] Step " << step_count + 1 << "/" << step_limit << std::endl;

        // 1. Capture State (Screenshot)
        std::string step_screenshot_path;
        if (step_count == 0 && !current_screenshot.empty()) {
            step_screenshot_path = current_screenshot;
        } else {
            // Capture new screenshot with retry logic
            int max_retries = 3;
            for (int retry = 0; retry < max_retries; retry++) {
                if (captureScreenshot(step_screenshot_path)) {
                    break;
                }
                std::cerr << "Screenshot retry " << (retry + 1) << "/" << max_retries << std::endl;
                platform_->sleepMs(1000);
            }
        }

        // Generate base64 for the screenshot
        std::string base64_image = "";
        if (!step_screenshot_path.empty()) {
            base64_image = glm_client_->base64_encode(step_screenshot_path);
        }

        if (base64_image.empty()) {
            std::cerr << "Warning: No screenshot available" << std::endl;
        }

        // Prune old images from history to save tokens
        for (auto& msg : conversation_history) {
            if (msg["role"] == "user" && msg.contains("content") && msg["content"].is_array()) {
                auto& content = msg["content"];
                for (auto it = content.begin(); it != content.end(); ) {
                    if ((*it).contains("type") && (*it)["type"] == "image_url") {
                        it = content.erase(it);
                    } else {
                        ++it;
                    }
                }
            }
        }

        // 2. Prepare Request
        AutoGLMRequest request;
        request.user_command = user_command;

        conversation_history.push_back(AutoGLMClient::createUserMessage(
            base64_image.empty() ? "Current State: (screenshot unavailable)" : "Current State:",
            base64_image
        ));

        request.history = conversation_history;

        // 3. Call GLM
        AutoGLMResponse response = glm_client_->processCommand(request);

        if (!response.success) {
            std::cerr << "GLM call failed: " << response.reasoning << std::endl;
            task.status = TaskStatus::Failed;
            task.error_message = "GLM call failed: " + response.reasoning;
            break;
        }

        // 4. Update History with Assistant Response
        std::string full_response_content = "";
        if (!response.thinking.empty()) {
            full_response_content += ".cycle" + response.thinking + ".cycle\n";
        }
        full_response_content += response.action;

        conversation_history.push_back(AutoGLMClient::createAssistantMessage(full_response_content));

        // 5. Execute Action
        bool should_finish = false;
        if (!executeAction(response.action, should_finish)) {
            std::cerr << "Action execution failed" << std::endl;
            conversation_history.push_back(AutoGLMClient::createUserMessage("Action failed to execute."));
        }

        if (should_finish) {
            task_completed = true;
            task.status = TaskStatus::Completed;

            ParsedAction final_act = parseActionString(response.action);
            if (final_act.type == "finish" && final_act.args.count("message")) {
                std::cout << "\n========================================" << std::endl;
                std::cout << "Task Finished: " << final_act.args["message"] << std::endl;
                std::cout << "========================================\n" << std::endl;
                task.error_message = final_act.args["message"];
            }
        }

        step_count++;
        platform_->sleepMs(1000);
    }

    if (!task_completed && task.status != TaskStatus::Failed) {
        task.status = TaskStatus::Failed;
        task.error_message = "Task exceeded step limit or failed without finish()";
    }

    // Log result
    if (task.status == TaskStatus::Completed) {
        std::cout << "[" << task.task_id << "] Task completed successfully" << std::endl;
    } else {
        std::cerr << "[" << task.task_id << "] Task failed: " << task.error_message << std::endl;
    }

    task.step_count = step_count;

    {
        std::lock_guard<std::mutex> lock(history_mutex_);
        task_history_.push_back(task);
    }

    return task;
}

TaskExecutor::ParsedAction TaskExecutor::parseActionString(const std::string& action_string) {
    ParsedAction result;

    std::string clean_str = action_string;
    clean_str.erase(0, clean_str.find_first_not_of(" \n\r\t"));
    clean_str.erase(clean_str.find_last_not_of(" \n\r\t") + 1);

    if (clean_str.find("finish(") == 0) {
        result.type = "finish";
        std::regex msg_regex("message\\s*=\\s*[\"']([^\"']*)[\"']");
        std::smatch match;
        if (std::regex_search(clean_str, match, msg_regex)) {
            result.args["message"] = match[1];
        }
    } else if (clean_str.find("do(") == 0) {
        std::regex action_regex("action\\s*=\\s*[\"']([^\"']*)[\"']");
        std::smatch match;
        if (std::regex_search(clean_str, match, action_regex)) {
            result.type = match[1];
        }

        std::regex arg_pair_regex("(\\w+)\\s*=\\s*(?:[\"']([^\"']*)[\"']|\\[([\\d,\\s]+)\\]|([^,\\s\\)]+))");
        auto words_begin = std::sregex_iterator(clean_str.begin(), clean_str.end(), arg_pair_regex);
        auto words_end = std::sregex_iterator();

        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            std::smatch match = *i;
            std::string key = match[1];
            std::string val_q = match[2];
            std::string val_a = match[3];
            std::string val_r = match[4];

            if (key == "action") continue;

            if (!val_q.empty()) result.args[key] = val_q;
            else if (!val_a.empty()) {
                std::string cleaned_val_a = val_a;
                cleaned_val_a.erase(std::remove(cleaned_val_a.begin(), cleaned_val_a.end(), ' '), cleaned_val_a.end());
                result.args[key] = cleaned_val_a;
            }
            else result.args[key] = val_r;
        }
    } else {
        result.type = "unknown";
        result.args["raw"] = clean_str;
    }

    return result;
}

std::pair<int, int> TaskExecutor::convertCoordinates(int rel_x, int rel_y) {
    // GLM uses 0-1000 relative coordinate system
    int abs_x = (rel_x * screen_width_) / 1000;
    int abs_y = (rel_y * screen_height_) / 1000;
    return {abs_x, abs_y};
}

void TaskExecutor::notifyAction(const ParsedAction& action) {
    try {
        json info;
        info["action"] = action.type;

        // Extract and convert coordinates for position-based actions
        std::string act = action.type;
        std::transform(act.begin(), act.end(), act.begin(), ::tolower);
        act.erase(std::remove(act.begin(), act.end(), ' '), act.end());

        if ((act == "tap" || act == "click" || act == "longpress" || act == "doubletap")
            && action.args.count("element")) {
            std::string coords = action.args.at("element");
            // Try [x, y] format first
            std::regex coord_regex("\\[?(\\d+),\\s*(\\d+)\\]?");
            std::smatch match;
            if (std::regex_search(coords, match, coord_regex)) {
                int rel_x = std::stoi(match[1]);
                int rel_y = std::stoi(match[2]);
                auto [abs_x, abs_y] = convertCoordinates(rel_x, rel_y);
                info["x"] = abs_x;
                info["y"] = abs_y;
            }
        } else if ((act == "swipe" || act == "scroll") && action.args.count("start")) {
            std::string start = action.args.at("start");
            size_t c = start.find(',');
            if (c != std::string::npos) {
                int x1 = std::stoi(start.substr(0, c));
                int y1 = std::stoi(start.substr(c + 1));
                auto [abs_x, abs_y] = convertCoordinates(x1, y1);
                info["x"] = abs_x;
                info["y"] = abs_y;
            }
            if (action.args.count("end")) {
                std::string end = action.args.at("end");
                size_t c2 = end.find(',');
                if (c2 != std::string::npos) {
                    int x2 = std::stoi(end.substr(0, c2));
                    int y2 = std::stoi(end.substr(c2 + 1));
                    auto [abs_x2, abs_y2] = convertCoordinates(x2, y2);
                    info["end_x"] = abs_x2;
                    info["end_y"] = abs_y2;
                }
            }
        }

        std::string jsonStr = info.dump();

        // Write to action event file for the Android client to observe
        std::ofstream actionFile("/data/local/tmp/.boji-agent-actions.jsonl", std::ios::app);
        if (actionFile.is_open()) {
            actionFile << jsonStr << "\n";
            actionFile.flush();
        }

        // Print tagged line to stdout so the server can detect and relay
        std::cout << "[AGENT_ACTION]" << jsonStr << std::endl;

        if (action_callback_) {
            action_callback_(jsonStr);
        }
    } catch (const std::exception& e) {
        std::cerr << "notifyAction error: " << e.what() << std::endl;
    }
}

bool TaskExecutor::executeAction(const std::string& action_string, bool& should_finish) {
    should_finish = false;
    ParsedAction action = parseActionString(action_string);

    if (action.type == "unknown") {
        std::cerr << "Could not parse action string: " << action.args["raw"] << std::endl;
        return false;
    }

    std::cout << "Executing Action: " << action.type << std::endl;

    if (action.type == "finish") {
        notifyAction(action);
        should_finish = true;
        return true;
    }

    notifyAction(action);

    std::string act = action.type;
    std::transform(act.begin(), act.end(), act.begin(), ::tolower);
    act.erase(std::remove(act.begin(), act.end(), ' '), act.end());

    if (act == "tap" || act == "click") return handleTap(action.args);
    if (act == "type" || act == "input" || act == "type_name") return handleType(action.args);
    if (act == "swipe" || act == "scroll") return handleSwipe(action.args);
    if (act == "launch" || act == "open") return handleLaunch(action.args);
    if (act == "back") return handleBack(action.args);
    if (act == "home") return handleHome(action.args);
    if (act == "wait" || act == "sleep") return handleWait(action.args);
    if (act == "longpress") return handleLongPress(action.args);
    if (act == "doubletap") return handleDoubleTap(action.args);

    std::cerr << "Unsupported action type: " << action.type << std::endl;
    return false;
}

bool TaskExecutor::handleTap(const std::map<std::string, std::string>& args) {
    if (args.count("element")) {
        std::string coords = args.at("element");
        size_t comma = coords.find(',');
        if (comma != std::string::npos) {
            int rel_x = std::stoi(coords.substr(0, comma));
            int rel_y = std::stoi(coords.substr(comma + 1));
            auto abs = convertCoordinates(rel_x, rel_y);
            std::cout << "    Tapping: (" << abs.first << ", " << abs.second << ")" << std::endl;
            return platform_->tap(abs.first, abs.second);
        }
    }
    return false;
}

bool TaskExecutor::handleType(const std::map<std::string, std::string>& args) {
    if (args.count("text")) {
        std::cout << "    Inputting text: \"" << args.at("text") << "\"" << std::endl;
        return platform_->inputText(args.at("text"));
    }
    return false;
}

bool TaskExecutor::handleSwipe(const std::map<std::string, std::string>& args) {
    if (args.count("start") && args.count("end")) {
        std::string start = args.at("start");
        std::string end = args.at("end");

        size_t c1 = start.find(',');
        size_t c2 = end.find(',');

        if (c1 != std::string::npos && c2 != std::string::npos) {
            int x1 = std::stoi(start.substr(0, c1));
            int y1 = std::stoi(start.substr(c1 + 1));
            int x2 = std::stoi(end.substr(0, c2));
            int y2 = std::stoi(end.substr(c2 + 1));

            auto p1 = convertCoordinates(x1, y1);
            auto p2 = convertCoordinates(x2, y2);

            std::cout << "    Swiping: (" << p1.first << "," << p1.second << ") -> ("
                     << p2.first << "," << p2.second << ")" << std::endl;
            return platform_->swipe(p1.first, p1.second, p2.first, p2.second, 500);
        }
    }
    return false;
}

bool TaskExecutor::handleLaunch(const std::map<std::string, std::string>& args) {
    if (args.count("app")) {
        std::string app_name = args.at("app");
        std::string package_name = getPackageName(app_name);
        if (package_name.empty()) {
            package_name = app_name;
        }
        std::string ability_name = getAbilityName(package_name);
        std::cout << "    Launching: " << app_name << " -> " << package_name << ":" << ability_name << std::endl;

        bool success = platform_->launchApp(package_name, ability_name);

        if (success) {
            std::cout << "    Waiting for app to start..." << std::endl;
            platform_->sleepMs(2000);
        }
        return success;
    }
    return false;
}

bool TaskExecutor::handleBack(const std::map<std::string, std::string>& args) {
    std::cout << "    Pressing Back" << std::endl;
    return platform_->pressBack();
}

bool TaskExecutor::handleHome(const std::map<std::string, std::string>& args) {
    std::cout << "    Pressing Home" << std::endl;
    return platform_->pressHome();
}

bool TaskExecutor::handleWait(const std::map<std::string, std::string>& args) {
    int ms = 1000;
    if (args.count("duration")) {
        std::string dur = args.at("duration");
        if (dur.find("seconds") != std::string::npos) {
            float sec = std::stof(dur.substr(0, dur.find(" ")));
            ms = static_cast<int>(sec * 1000);
        }
    }
    std::cout << "    Waiting " << ms << "ms" << std::endl;
    platform_->sleepMs(ms);
    return true;
}

bool TaskExecutor::handleLongPress(const std::map<std::string, std::string>& args) {
    if (args.count("element")) {
        std::string elem_str = args.at("element");
        std::regex coord_regex("\\[(\\d+),\\s*(\\d+)\\]");
        std::smatch match;
        if (std::regex_search(elem_str, match, coord_regex)) {
            int rel_x = std::stoi(match[1]);
            int rel_y = std::stoi(match[2]);
            auto [abs_x, abs_y] = convertCoordinates(rel_x, rel_y);
            std::cout << "    Long pressing: (" << abs_x << ", " << abs_y << ")" << std::endl;
            return platform_->longPress(abs_x, abs_y);
        }
    }
    std::cerr << "handleLongPress: missing element coordinates" << std::endl;
    return false;
}

bool TaskExecutor::handleDoubleTap(const std::map<std::string, std::string>& args) {
    if (args.count("element")) {
        std::string elem_str = args.at("element");
        std::regex coord_regex("\\[(\\d+),\\s*(\\d+)\\]");
        std::smatch match;
        if (std::regex_search(elem_str, match, coord_regex)) {
            int rel_x = std::stoi(match[1]);
            int rel_y = std::stoi(match[2]);
            auto [abs_x, abs_y] = convertCoordinates(rel_x, rel_y);
            std::cout << "    Double tapping: (" << abs_x << ", " << abs_y << ")" << std::endl;
            return platform_->doubleTap(abs_x, abs_y);
        }
    }
    std::cerr << "handleDoubleTap: missing element coordinates" << std::endl;
    return false;
}

std::vector<Task> TaskExecutor::getTaskHistory() const {
    std::lock_guard<std::mutex> lock(history_mutex_);
    return task_history_;
}

std::string TaskExecutor::generateTaskId() {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dis(1000, 9999);
    auto now = std::chrono::system_clock::now();
    auto timestamp = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << "task_" << timestamp << "_" << dis(gen);
    return ss.str();
}

std::string TaskExecutor::getCurrentTimestamp() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    struct tm tm_buf;
#ifdef __linux__
    localtime_r(&time, &tm_buf);
#else
    localtime_s(&tm_buf, &time);
#endif
    ss << std::put_time(&tm_buf, "%Y-%m-%d %H:%M:%S");
    return ss.str();
}
