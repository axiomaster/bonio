#pragma once

#include <string>
#include <functional>
#include <memory>

// Use nlohmann::json for request/response structures
#include <nlohmann/json.hpp>
#include <vector>

// Forward declaration
class HttpClient;

struct AutoGLMRequest {
    std::string user_command;
    std::string screenshot_path;
    std::string ui_tree_json;
    
    // Conversation history - maintained by TaskExecutor/Caller
    std::vector<nlohmann::json> history;
};

struct AutoGLMResponse {
    std::string action_plan; // Kept for backward compatibility, but contains the 'action' string
    std::string reasoning;   // Contains 'thinking'
    bool success;
    
    // New fields for specific AutoGLM parts
    std::string thinking;
    std::string action;
};

class AutoGLMClient {
public:
    AutoGLMClient();
    ~AutoGLMClient();

    bool initialize();
    AutoGLMResponse processCommand(const AutoGLMRequest& request);
    
    // Helper to create messages
    static nlohmann::json createSystemMessage(const std::string& content);
    static nlohmann::json createUserMessage(const std::string& text, const std::string& image_base64 = "");
    static nlohmann::json createAssistantMessage(const std::string& content);

    // Helper function to encode file to base64
    std::string base64_encode(const std::string& file_path);

private:
    std::unique_ptr<HttpClient> http_client_;
    std::string api_endpoint_;
    std::string api_key_;
    std::string api_model_;

    // Helper function to build JSON request body
    std::string buildRequestBody(const AutoGLMRequest& request);

    // Helper function to parse API response
    AutoGLMResponse parseResponse(const std::string& response_body, int status_code);

    // Check if client is in test/mock mode
    bool isTestMode() const;
};
