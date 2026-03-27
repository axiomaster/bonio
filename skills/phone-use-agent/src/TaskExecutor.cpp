#include "TaskExecutor.h"
#include "Config.h"
#include "ConfigManager.h"
#include "AppPackages.h"
#include <iostream>
#include <chrono>
#include <sstream>
#include <random>
#include <iomanip>
#include <ctime>
#include <nlohmann/json.hpp>
#include <regex>
#include <unistd.h>

using json = nlohmann::json;

// External global interruption flag (defined in main.cpp)
extern std::atomic<bool> g_interrupted;

TaskExecutor::TaskExecutor() {
}

TaskExecutor::TaskExecutor(std::shared_ptr<UIInspector> ui_inspector,
                           std::shared_ptr<AppManager> app_manager)
    : ui_inspector_(ui_inspector),
      app_manager_(app_manager) {
}

TaskExecutor::~TaskExecutor() {
}

bool TaskExecutor::initialize() {
    // Load configuration
    Config::getInstance().loadFromFile();

    glm_client_ = std::make_unique<AutoGLMClient>();
    if (!glm_client_->initialize()) {
        std::cerr << "Failed to initialize AutoGLM client" << std::endl;
        return false;
    }

    if (!ui_inspector_) {
        // Only initialize if not injected
        ui_inspector_ = std::make_unique<UIInspector>();
        if (!ui_inspector_->initialize()) {
            std::cerr << "Failed to initialize UIInspector" << std::endl;
            return false;
        }
    }

    if (!app_manager_) {
        app_manager_ = std::make_unique<AppManager>();
        if (!app_manager_->initialize()) {
            std::cerr << "Failed to initialize AppManager" << std::endl;
            return false;
        }
    }

    std::cout << "TaskExecutor initialized" << std::endl;
    return true;
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
        "" // No image for initial prompt, will add in loop if needed, or loop 0
    ));
    
    // Loop control
    int step_limit = max_step_limit_;
    int step_count = 0;
    bool task_completed = false;
    std::string last_screenshot_path = current_screenshot;
    
    // If we have an initial screenshot, we should append it to the history as a separate user message or combined
    // For simplicity, let's treat the loop as:
    // 1. Observe (Screenshot) 
    // 2. Think & Act (Call GLM)
    // 3. Execute
    
    // Special case for step 0: We already have the command, and potentially a screenshot
    // Let's structure the loop to handle the "next step" logic
    
    while (step_count < step_limit && !task_completed && !isInterrupted()) {
        // Check for interruption at the start of each iteration
        if (isInterrupted()) {
            std::cout << "[" << task.task_id << "] Interrupted by user" << std::endl;
            task.status = TaskStatus::Interrupted;
            task.error_message = "Task interrupted by user (Ctrl+C)";
            break;
        }

        std::cout << "[" << task.task_id << "] Step " << step_count + 1 << "/" << step_limit << std::endl;
        
        // 1. Capture State (Screenshot) - unless it's step 0 and we passed one in?
        // Actually, always capture fresh state to be safe, or use passed one for first step
        std::string step_screenshot_path;
        if (step_count == 0 && !current_screenshot.empty()) {
            step_screenshot_path = current_screenshot;
        } else {
            // Capture new screenshot with retry logic
            int max_retries = 3;
            std::string screenshot_dir = "/data/local/tmp";
            // Ensure directory exists
            // std::string mkdir_cmd = "mkdir -p " + screenshot_dir; // /data/local/tmp always exists
            // system(mkdir_cmd.c_str());

            for (int retry = 0; retry < max_retries; retry++) {
                UIState state = ui_inspector_->captureUIState(screenshot_dir);
                step_screenshot_path = state.screenshot_path;
                if (!step_screenshot_path.empty()) {
                    break;  // Success
                }
                std::cerr << "Screenshot retry " << (retry + 1) << "/" << max_retries << std::endl;
                usleep(1000 * 1000);  // 1 second in microseconds
            }
        }
        
        // Generate base64 for the screenshot
        std::string base64_image = "";
        if (!step_screenshot_path.empty()) {
            base64_image = glm_client_->base64_encode(step_screenshot_path);
        }
        
        // If screenshot failed completely, we need to handle it
        if (base64_image.empty()) {
            std::cerr << "Warning: No screenshot available, adding text-only message" << std::endl;
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
        request.user_command = user_command; // Just for logging/context
        
        // We will append the current observation to history
        // Only add image if we have one
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
        // We reconstruct the assistant message from thinking + action
        std::string full_response_content = "";
        if (!response.thinking.empty()) {
            full_response_content += "<think>" + response.thinking + "</think>\n";
        }
        full_response_content += response.action; // Action content is the raw text like do(...)
        
        conversation_history.push_back(AutoGLMClient::createAssistantMessage(full_response_content));
        
        // 5. Execute Action
        bool should_finish = false;
        if (!executeAction(response.action, should_finish)) {
             std::cerr << "Action execution failed" << std::endl;
             // We can choose to retry or fail. For now, fail.
             // Or maybe feed back the error to the model?
             // Let's Try feeding back error
             conversation_history.push_back(AutoGLMClient::createUserMessage("Action failed to execute."));
        }
        
        if (should_finish) {
            task_completed = true;
            task.status = TaskStatus::Completed;

            // Parse message from finish command if available
            ParsedAction final_act = parseActionString(response.action);
            if (final_act.type == "finish" && final_act.args.count("message")) {
                std::cout << "\n========================================" << std::endl;
                std::cout << "Task Finished: " << final_act.args["message"] << std::endl;
                std::cout << "========================================\n" << std::endl;
                task.error_message = final_act.args["message"];
            }
        }
        
        step_count++;

        // Small delay
        usleep(1000 * 1000);  // 1 second in microseconds
    }
    
    if (!task_completed && task.status != TaskStatus::Failed) {
        task.status = TaskStatus::Failed;
        task.error_message = "Task exceeded step limit or failed without finish()";
    }

    // --- AGENT LOOP END ---

    // Clean up screenshot files if needed? 
    // (Usually strictly temporary files in /data/local/tmp are cleaned by system or overwritten)

    // Log result
    // Log result
    if (task.status == TaskStatus::Completed) {
        std::cout << "[" << task.task_id << "] Task completed successfully" << std::endl;
    } else {
        std::cerr << "[" << task.task_id << "] Task failed: " << task.error_message << std::endl;
    }

    // Store step count
    task.step_count = step_count;

    // Add to history
    {
        std::lock_guard<std::mutex> lock(history_mutex_);
        task_history_.push_back(task);
    }

    return task;
}

TaskExecutor::ParsedAction TaskExecutor::parseActionString(const std::string& action_string) {
    ParsedAction result;
    
    std::string clean_str = action_string;
    // Trim potential whitespace
    clean_str.erase(0, clean_str.find_first_not_of(" \n\r\t"));
    clean_str.erase(clean_str.find_last_not_of(" \n\r\t") + 1);
    
    if (clean_str.find("finish(") == 0) {
        result.type = "finish";
        // Extract message (handles both double and single quotes)
        std::regex msg_regex("message\\s*=\\s*[\"']([^\"']*)[\"']");
        std::smatch match;
        if (std::regex_search(clean_str, match, msg_regex)) {
             result.args["message"] = match[1];
        }
    } else if (clean_str.find("do(") == 0) {
        // Extract action type
        std::regex action_regex("action\\s*=\\s*[\"']([^\"']*)[\"']");
        std::smatch match;
        if (std::regex_search(clean_str, match, action_regex)) {
            result.type = match[1];
        }
        
        // Extract other args
        // Matches key="value" or key=[x,y] or key=value
        // Improved regex to handle optional spaces around = and different value types
        std::regex arg_pair_regex("(\\w+)\\s*=\\s*(?:[\"']([^\"']*)[\"']|\\[([\\d,\\s]+)\\]|([^,\\s\\)]+))");
        auto words_begin = std::sregex_iterator(clean_str.begin(), clean_str.end(), arg_pair_regex);
        auto words_end = std::sregex_iterator();

        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            std::smatch match = *i;
            std::string key = match[1];
            std::string val_q = match[2]; // Quoted string
            std::string val_a = match[3]; // Array [x,y]
            std::string val_r = match[4]; // Raw/Other
            
            if (key == "action") continue; // Already extracted
            
            if (!val_q.empty()) result.args[key] = val_q;
            else if (!val_a.empty()) {
                // Remove spaces within [x, y] to get "x,y"
                std::string cleaned_val_a = val_a;
                cleaned_val_a.erase(std::remove(cleaned_val_a.begin(), cleaned_val_a.end(), ' '), cleaned_val_a.end());
                result.args[key] = cleaned_val_a;
            }
            else result.args[key] = val_r;
        }
    } else {
        // Fallback for raw action name or unknown format
        result.type = "unknown";
        result.args["raw"] = clean_str;
    }
    
    return result;
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
        should_finish = true;
        return true;
    }
    
    // Normalize action names (case-insensitive or mapping)
    std::string act = action.type;
    std::transform(act.begin(), act.end(), act.begin(), ::tolower);
    
    // Remove spaces for matching (e.g., "long press" -> "longpress")
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

std::pair<int, int> TaskExecutor::convertCoordinates(int rel_x, int rel_y) {
    // Open-AutoGLM uses 0-999 relative coordinate system
    // Convert relative coordinates (0-999) to absolute pixels
    // Formula: x = int(element[0] / 1000 * screen_width)

    // Actual screen dimensions
    int screen_w = 1320;
    int screen_h = 2848;

    int abs_x = (rel_x * screen_w) / 1000;
    int abs_y = (rel_y * screen_h) / 1000;

    return {abs_x, abs_y};
}

bool TaskExecutor::handleTap(const std::map<std::string, std::string>& args) {
    if (args.count("element")) {
        std::string coords = args.at("element"); // "x,y"
        size_t comma = coords.find(',');
        if (comma != std::string::npos) {
            int rel_x = std::stoi(coords.substr(0, comma));
            int rel_y = std::stoi(coords.substr(comma + 1));
            auto abs = convertCoordinates(rel_x, rel_y);
            return tapCoordinates(abs.first, abs.second);
        }
    }
    return false;
}

bool TaskExecutor::handleType(const std::map<std::string, std::string>& args) {
    if (args.count("text")) {
        return inputText(args.at("text"));
    }
    return false;
}

bool TaskExecutor::handleSwipe(const std::map<std::string, std::string>& args) {
    if (args.count("start") && args.count("end")) {
        std::string start = args.at("start");
        std::string end = args.at("end");
        
        int x1, y1, x2, y2;
        size_t c1 = start.find(',');
        size_t c2 = end.find(',');
        
        if (c1 != std::string::npos && c2 != std::string::npos) {
             x1 = std::stoi(start.substr(0, c1));
             y1 = std::stoi(start.substr(c1 + 1));
             x2 = std::stoi(end.substr(0, c2));
             y2 = std::stoi(end.substr(c2 + 1));
             
             auto p1 = convertCoordinates(x1, y1);
             auto p2 = convertCoordinates(x2, y2);
             
             return swipe(p1.first, p1.second, p2.first, p2.second, 500);
        }
    }
    return false;
}

bool TaskExecutor::handleLaunch(const std::map<std::string, std::string>& args) {
    if (args.count("app")) {
        std::string app_name = args.at("app");
        // Look up bundle name from app display name
        std::string bundle_name = getPackageName(app_name);
        if (bundle_name.empty()) {
            // Assume it's already a bundle name
            bundle_name = app_name;
        }
        // Get the ability name for this bundle
        std::string ability_name = getAbilityName(bundle_name);
        std::cout << "    Launching: " << app_name << " -> " << bundle_name << ":" << ability_name << std::endl;
        bool success = app_manager_->launchApp(bundle_name, ability_name);
        
        // Wait for app to fully start before taking screenshot
        if (success) {
            std::cout << "    Waiting for app to start..." << std::endl;
            usleep(2000 * 1000);  // 2 seconds in microseconds
        }
        return success;
    }
    return false;
}

bool TaskExecutor::handleBack(const std::map<std::string, std::string>& args) {
    // HarmonyOS uses uitest uiInput keyEvent Back
    system("/bin/uitest uiInput keyEvent Back");
    return true;
}

bool TaskExecutor::handleHome(const std::map<std::string, std::string>& args) {
    // HarmonyOS uses uitest uiInput keyEvent Home
    system("/bin/uitest uiInput keyEvent Home");
    return true;
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
    usleep(ms * 1000);  // Convert milliseconds to microseconds
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
            // HarmonyOS uses uitest uiInput longClick
            std::string cmd = "/bin/uitest uiInput longClick " + std::to_string(abs_x) + " " + std::to_string(abs_y);
            int result = system(cmd.c_str());
            return (result == 0);
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
            // HarmonyOS uses uitest uiInput doubleClick
            std::string cmd = "/bin/uitest uiInput doubleClick " + std::to_string(abs_x) + " " + std::to_string(abs_y);
            int result = system(cmd.c_str());
            return (result == 0);
        }
    }
    std::cerr << "handleDoubleTap: missing element coordinates" << std::endl;
    return false;
}

// ... (Existing Primitives below) ...

bool TaskExecutor::executeActionPlan(const std::string& action_plan) {
    return false; // Deprecated
}

bool TaskExecutor::tapElement(const std::string& element_id) {
    // ... Existing implementation ...
     return tapCoordinates(0, 0); // Placeholder
}

bool TaskExecutor::tapCoordinates(int x, int y) {
    std::cout << "    Tapping coordinates: (" << x << ", " << y << ")" << std::endl;
    // HarmonyOS uses uitest uiInput click
    std::string cmd = "/bin/uitest uiInput click " + std::to_string(x) + " " + std::to_string(y);
    int result = system(cmd.c_str());
    return (result == 0);
}

bool TaskExecutor::inputText(const std::string& text) {
    std::cout << "    Inputting text: \"" << text << "\"" << std::endl;
    // HarmonyOS uses uitest uiInput text
    // Escape quotes in the text
    std::string escaped_text = text;
    size_t pos = 0;
    while ((pos = escaped_text.find('"', pos)) != std::string::npos) {
        escaped_text.replace(pos, 1, "\\\"");
        pos += 2;
    }
    std::string cmd = "/bin/uitest uiInput text \"" + escaped_text + "\"";
    int result = system(cmd.c_str());
    return (result == 0);
}

bool TaskExecutor::swipe(int x1, int y1, int x2, int y2, int duration_ms) {
    std::cout << "    Swiping: (" << x1 << "," << y1 << ") -> ("
             << x2 << "," << y2 << ") duration=" << duration_ms << "ms" << std::endl;
    // HarmonyOS uses uitest uiInput swipe
    std::string cmd = "/bin/uitest uiInput swipe " + std::to_string(x1) + " " +
                     std::to_string(y1) + " " +
                     std::to_string(x2) + " " +
                     std::to_string(y2) + " " +
                     std::to_string(duration_ms);
    int result = system(cmd.c_str());
    return (result == 0);
}

bool TaskExecutor::waitForElement(const std::string& element_id, int timeout_ms) {
    return true;
}

bool TaskExecutor::launchApp(const std::string& bundle_name) {
    std::cout << "    Launching app: " << bundle_name << std::endl;
    return app_manager_->launchApp(bundle_name);
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

bool TaskExecutor::isValidElementId(const std::string& element_id) {
    return true;
}
