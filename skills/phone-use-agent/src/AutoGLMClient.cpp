#include "AutoGLMClient.h"
#include "HttpClient.h"
#include "ConfigManager.h"
#include "Config.h"
#include <nlohmann/json.hpp>
#include <iostream>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <vector>

using json = nlohmann::json;

#define LOG_TAG "AutoGLMClient"
#define MAX_SCREENSHOT_SIZE_MB 5

AutoGLMClient::AutoGLMClient() {
}

AutoGLMClient::~AutoGLMClient() {
}

bool AutoGLMClient::isTestMode() const {
    // Check if we're using a placeholder API key
    return api_key_ == "YOUR_API_KEY_HERE" ||
           api_key_.empty();
}

bool AutoGLMClient::initialize() {
    // Create and initialize HTTP client
    http_client_ = std::make_unique<HttpClient>();

    // Load config
    api_key_ = Config::getInstance().getGlmApiKey();
    api_endpoint_ = Config::getInstance().getGlmEndpoint();
    api_model_ = Config::getInstance().getModel();
    
    // Warn if API key is missing
    if (api_key_.empty() || api_key_ == "YOUR_API_KEY_HERE") {
        std::cerr << "[" << LOG_TAG << "] Warning: No API key configured" << std::endl;
    }

    if (!http_client_->initialize()) {
        std::cerr << "[" << LOG_TAG << "] Failed to initialize HTTP client" << std::endl;
        return false;
    }

    // Set timeout to 120 seconds for API calls (reasoning models can take time)
    http_client_->setTimeout(120);

    std::cout << "[" << LOG_TAG << "] AutoGLM Client initialized" << std::endl;
    std::cout << "[" << LOG_TAG << "] API Endpoint: " << api_endpoint_ << std::endl;

    if (isTestMode()) {
        std::cout << "[" << LOG_TAG << "] WARNING: Running in TEST MODE - using mock API" << std::endl;
    }

    return true;
}

std::string AutoGLMClient::base64_encode(const std::string& file_path) {
    if (file_path.empty()) return "";

    // Read file content
    std::ifstream file(file_path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "[" << LOG_TAG << "] Failed to open file: " << file_path << std::endl;
        return "";
    }

    // Read file into buffer
    std::vector<uint8_t> buffer;
    file.seekg(0, std::ios::end);
    size_t size = file.tellg();
    file.seekg(0, std::ios::beg);

    // Check file size limit
    const size_t max_size = MAX_SCREENSHOT_SIZE_MB * 1024 * 1024;
    if (size > max_size) {
        std::cerr << "[" << LOG_TAG << "] File too large: " << size
                  << " bytes (max: " << max_size << " bytes)" << std::endl;
        return "";
    }

    buffer.resize(size);
    file.read(reinterpret_cast<char*>(buffer.data()), size);
    file.close();

    // Base64 encoding
    static const std::string base64_chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "abcdefghijklmnopqrstuvwxyz"
        "0123456789+/";

    std::string encoded;
    int i = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];
    size_t pos = 0;

    while (pos < buffer.size()) {
        char_array_3[i++] = buffer[pos++];
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;

            for (i = 0; i < 4; i++) {
                encoded += base64_chars[char_array_4[i]];
            }
            i = 0;
        }
    }

    if (i > 0) {
        for (int j = i; j < 3; j++) {
            char_array_3[j] = '\0';
        }

        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);

        for (int j = 0; j < i + 1; j++) {
            encoded += base64_chars[char_array_4[j]];
        }

        while (i++ < 3) {
            encoded += '=';
        }
    }

    std::cout << "[" << LOG_TAG << "] Base64 encoded " << size
              << " bytes to " << encoded.length() << " characters" << std::endl;

    return encoded;
}

json AutoGLMClient::createSystemMessage(const std::string& content) {
    json msg;
    msg["role"] = "system";
    msg["content"] = content;
    return msg;
}

json AutoGLMClient::createUserMessage(const std::string& text, const std::string& image_base64) {
    json msg;
    msg["role"] = "user";
    
    // Content array for multimodal input
    json content_array = json::array();

    // 1. Add text logic
    json text_part;
    text_part["type"] = "text";
    text_part["text"] = text;
    content_array.push_back(text_part);

    // 2. Add image logic (if specific screenshot exists)
    if (!image_base64.empty()) {
        json image_part;
        image_part["type"] = "image_url";
        image_part["image_url"] = {
            {"url", "data:image/png;base64," + image_base64}
        };
        content_array.push_back(image_part);
    }
    
    msg["content"] = content_array;
    return msg;
}

json AutoGLMClient::createAssistantMessage(const std::string& content) {
    json msg;
    msg["role"] = "assistant";
    msg["content"] = content;
    return msg;
}

std::string AutoGLMClient::buildRequestBody(const AutoGLMRequest& request) {
    json request_json;

    // GLM API format - use configured model
    request_json["model"] = api_model_.empty() ? "autoglm-phone" : api_model_;

    // Build messages array
    json messages = json::array();

    // If history is provided, use it
    if (!request.history.empty()) {
        for (const auto& msg : request.history) {
            messages.push_back(msg);
        }
    } else {
        // Fallback for old style calls (single shot)
        // System prompt
        messages.push_back(createSystemMessage(
            "You are a smart agent controlling a HarmonyOS phone. "
            "Return strictly JSON format: {\"actions\": [...]} without markdown block."));
            
        // User message
        std::string base64_image = "";
        std::stringstream text_content;
        text_content << "User command: " << request.user_command << "\n\n";
        
        if (!request.screenshot_path.empty()) {
            base64_image = base64_encode(request.screenshot_path);
        }
        
        if (!request.ui_tree_json.empty()) {
            text_content << "[UI context: " << request.ui_tree_json << "]";
        }
        
        messages.push_back(createUserMessage(text_content.str(), base64_image));
    }
    
    request_json["messages"] = messages;

    // Serialize to string
    std::string body = request_json.dump();
    std::cout << "[" << LOG_TAG << "] Request body size: " << body.length() << " bytes" << std::endl;

    return body;
}

AutoGLMResponse AutoGLMClient::parseResponse(const std::string& response_body, int status_code) {
    AutoGLMResponse response;
    response.success = false;
    response.thinking = "";
    response.action = "";
    response.action_plan = "";

    if (status_code != 200) {
        response.reasoning = "HTTP error: " + std::to_string(status_code);
        return response;
    }

    try {
        // Parse JSON response using nlohmann/json
        json response_json = json::parse(response_body);

        // Check for GLM API error
        if (response_json.contains("error")) {
            std::string error = response_json["error"].is_string() ?
                response_json["error"].get<std::string>() :
                response_json["error"].dump();
            response.reasoning = "API error: " + error;
            return response;
        }

        // Extract content from GLM API response
        std::string content;
        if (response_json.contains("choices") && response_json["choices"].is_array()) {
            auto choices = response_json["choices"];
            if (choices.size() > 0 && choices[0].contains("message")) {
                auto msg = choices[0]["message"];
                if (msg.contains("content")) {
                    content = msg["content"].get<std::string>();
                    
                    // Parse content using logic from Open-AutoGLM reference client.py
                    // Logic: 
                    // 1. <think>...</think><answer>...</answer>
                    // 2. finish(message= OR do(action=
                    
                    std::string thinking_part, action_part;
                    
                    if (content.find("<answer>") != std::string::npos) {
                        // XML style
                        size_t split_pos = content.find("<answer>");
                        thinking_part = content.substr(0, split_pos);
                        action_part = content.substr(split_pos);
                        
                        // Clean tags
                        size_t think_start = thinking_part.find("<think>");
                        size_t think_end = thinking_part.find("</think>");
                        if (think_start != std::string::npos && think_end != std::string::npos) {
                            thinking_part = thinking_part.substr(think_start + 7, think_end - (think_start + 7));
                        }
                        
                        size_t answer_start = action_part.find("<answer>");
                        size_t answer_end = action_part.find("</answer>");
                        if (answer_start != std::string::npos && answer_end != std::string::npos) {
                            action_part = action_part.substr(answer_start + 8, answer_end - (answer_start + 8));
                        } else if (answer_start != std::string::npos) {
                             action_part = action_part.substr(answer_start + 8);
                        }
                    } else if (content.find("finish(message=") != std::string::npos) {
                        size_t split_pos = content.find("finish(message=");
                        thinking_part = content.substr(0, split_pos);
                        action_part = content.substr(split_pos);
                    } else if (content.find("do(action=") != std::string::npos) {
                        size_t split_pos = content.find("do(action=");
                        thinking_part = content.substr(0, split_pos);
                        action_part = content.substr(split_pos);
                    } else {
                        // Fallback
                        action_part = content;
                    }
                    
                    // Cleanup newlines/spaces
                    thinking_part.erase(0, thinking_part.find_first_not_of(" \n\r\t"));
                    thinking_part.erase(thinking_part.find_last_not_of(" \n\r\t") + 1);
                    action_part.erase(0, action_part.find_first_not_of(" \n\r\t"));
                    action_part.erase(action_part.find_last_not_of(" \n\r\t") + 1);
                    
                    response.thinking = thinking_part;
                    response.action = action_part;
                    response.reasoning = thinking_part;
                    response.action_plan = action_part; // For compatibility
                    response.success = true;
                }
            }
        }

        // If no content found
        if (response.action.empty()) {
            response.reasoning = "No action generated in API response";
        }

    } catch (const json::parse_error& e) {
        response.reasoning = "Failed to parse API response: " + std::string(e.what());
        std::cerr << "[" << LOG_TAG << "] JSON parse error: " << e.what() << std::endl;
        std::cerr << "[" << LOG_TAG << "] Response body: " << response_body << std::endl;
    } catch (const std::exception& e) {
        response.reasoning = "Unexpected error parsing response: " + std::string(e.what());
        std::cerr << "[" << LOG_TAG << "] Unexpected error: " << e.what() << std::endl;
    }

    return response;
}

AutoGLMResponse AutoGLMClient::processCommand(const AutoGLMRequest& request) {
    std::cout << "[" << LOG_TAG << "] Processing command via AutoGLM..." << std::endl;

    AutoGLMResponse response;
    response.success = false;

    // Test mode: Return mock response
    if (isTestMode()) {
        std::cout << "[" << LOG_TAG << "] TEST MODE: Returning mock response" << std::endl;
        response.thinking = "This is a test run.";
        response.action = "do(action=\"Wait\", duration=\"0.5 seconds\")";
        response.reasoning = response.thinking;
        response.action_plan = response.action;
        response.success = true;
        return response;
    }

    if (!http_client_) {
        response.reasoning = "HTTP client not initialized";
        return response;
    }

    // Build request body
    std::string request_body = buildRequestBody(request);

    // Prepare headers
    std::map<std::string, std::string> headers;
    headers["Authorization"] = "Bearer " + api_key_;
    headers["Content-Type"] = "application/json";
    headers["Accept"] = "application/json";

    // Make API request (Standard Chat Completions Endpoint)
    std::string url = api_endpoint_; // Endpoint is already full path in Config.h
    std::cout << "[" << LOG_TAG << "] Sending request to: " << url << std::endl;

    HttpResponse http_response = http_client_->post(url, request_body, headers);

    if (!http_response.success) {
        response.reasoning = "API request failed: " + http_response.error;
        std::cerr << "[" << LOG_TAG << "] " << response.reasoning << " (Status: " << http_response.status_code << ")" << std::endl;
        std::cerr << "[" << LOG_TAG << "] Response Body: " << http_response.body << std::endl;
        return response;
    }

    // Parse response
    response = parseResponse(http_response.body, http_response.status_code);

    std::cout << "[" << LOG_TAG << "] Command processed "
              << (response.success ? "successfully" : "with errors") << std::endl;
    if (response.success) {
        std::cout << "[" << LOG_TAG << "] Thinking: " << response.thinking << std::endl;
        std::cout << "[" << LOG_TAG << "] Action: " << response.action << std::endl;
    }

    return response;
}
