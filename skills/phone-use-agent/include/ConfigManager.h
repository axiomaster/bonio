#pragma once

#include <string>
#include "Config.h"

class Config {
public:
    static Config& getInstance();

    // API Key management
    void setApiKey(const std::string& key) { glm_api_key_ = key; }
    std::string getApiKey() const { return glm_api_key_; }
    // Alias for compatibility
    std::string getGlmApiKey() const { return glm_api_key_; }

    // Endpoint management
    void setEndpoint(const std::string& endpoint) { glm_endpoint_ = endpoint; }
    std::string getEndpoint() const { return glm_endpoint_; }
    // Alias for compatibility
    std::string getGlmEndpoint() const { return glm_endpoint_; }

    // System prompt for GLM model
    std::string getSystemPrompt() const;
    void setSystemPrompt(const std::string& prompt) { system_prompt_ = prompt; }

    // Model management
    void setModel(const std::string& model) { glm_model_ = model; }
    std::string getModel() const { return glm_model_; }

    // Config file operations
    bool loadFromFile(const std::string& config_file = DEFAULT_CONFIG_PATH);
    bool saveToFile(const std::string& config_file = DEFAULT_CONFIG_PATH);

    // Validation
    bool isValid() const;

private:
    Config();
    ~Config() = default;

    // Delete copy constructor and assignment operator
    Config(const Config&) = delete;
    Config& operator=(const Config&) = delete;

    // Helper
    std::string trim(const std::string& str) const;
    std::string getDefaultSystemPrompt() const;

    // Configuration values
    std::string glm_api_key_;
    std::string glm_endpoint_;
    std::string glm_model_;
    std::string system_prompt_;
};
