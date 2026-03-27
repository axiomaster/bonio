#pragma once

#include <string>

// Version constant
constexpr const char* VERSION = "1.0.0";

// Config file path
constexpr const char* DEFAULT_CONFIG_PATH = "/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf";

// Temp directory
constexpr const char* TEMP_DIR = "/data/local/tmp";

// Screenshot directory
constexpr const char* SCREENSHOT_DIR = "/data/local/.phone-use-harmonyos";

// API defaults
constexpr const char* DEFAULT_API_ENDPOINT = "https://open.bigmodel.cn/api/paas/v4/chat/completions";
constexpr int DEFAULT_TIMEOUT_SECONDS = 30;
constexpr int MAX_TASK_STEPS = 20;
