#include "ConfigManager.h"
#include "SystemPrompt.h"
#include <iostream>
#include <sstream>
#include <fstream>
#include <algorithm>

Config& Config::getInstance() {
    static Config instance;
    return instance;
}

Config::Config()
    : glm_api_key_("YOU-API-KEY")
    , glm_endpoint_("https://open.bigmodel.cn/api/paas/v4/chat/completions")
    , glm_model_("autoglm-phone")
    , system_prompt_("") {
}

std::string Config::trim(const std::string& str) const {
    size_t first = str.find_first_not_of(" \t\n\r");
    if (first == std::string::npos) return "";
    size_t last = str.find_last_not_of(" \t\n\r");
    return str.substr(first, last - first + 1);
}

std::string Config::getSystemPrompt() const {
    if (!system_prompt_.empty()) {
        return system_prompt_;
    }
    return getDefaultSystemPrompt();
}

std::string Config::getDefaultSystemPrompt() const {
    return ::getDefaultSystemPrompt();
}

bool Config::loadFromFile(const std::string& config_file) {
    std::ifstream file(config_file);
    if (!file.is_open()) {
        std::cerr << "[Config] Config file not found: " << config_file << std::endl;
        std::cerr << "[Config] Using default configuration" << std::endl;
        return false;
    }

    std::string line;

    while (std::getline(file, line)) {
        line = trim(line);

        // Skip empty lines and comments
        if (line.empty() || line[0] == '#') {
            continue;
        }

        // Parse key=value
        size_t pos = line.find('=');
        if (pos != std::string::npos) {
            std::string key = trim(line.substr(0, pos));
            std::string value = trim(line.substr(pos + 1));

            if (key == "GLM_API_KEY") {
                glm_api_key_ = value;
            } else if (key == "GLM_ENDPOINT") {
                glm_endpoint_ = value;
            } else if (key == "GLM_MODEL") {
                glm_model_ = value;
            } else {
                std::cout << "[Config] Unknown key: " << key << std::endl;
            }
        }
    }

    file.close();
    std::cout << "[Config] Loaded configuration from: " << config_file << std::endl;
    return true;
}

bool Config::saveToFile(const std::string& config_file) {
    std::ofstream file(config_file);
    if (!file.is_open()) {
        std::cerr << "[Config] Failed to create config file: " << config_file << std::endl;
        return false;
    }

    file << "# phone-use-harmonyos Configuration\n";
    file << "# Generated automatically\n\n";
    file << "GLM_API_KEY=" << glm_api_key_ << "\n";
    file << "GLM_ENDPOINT=" << glm_endpoint_ << "\n";
    file << "GLM_MODEL=" << glm_model_ << "\n";

    file.close();
    std::cout << "[Config] Saved configuration to: " << config_file << std::endl;
    return true;
}

bool Config::isValid() const {
    if (glm_api_key_.empty() || glm_api_key_ == "YOUR_API_KEY_HERE") {
        std::cerr << "[Config] Invalid: GLM_API_KEY not configured" << std::endl;
        return false;
    }

    if (glm_endpoint_.empty()) {
        std::cerr << "[Config] Invalid: GLM_ENDPOINT not configured" << std::endl;
        return false;
    }

    return true;
}
