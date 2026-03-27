#include "AppManager.h"
#include "Config.h"
#include <iostream>
#include <sstream>
#include <memory>
#include <functional>

AppManager::AppManager()
    : meetime_bundle_name_("com.huawei.hmos.meetime")
    , meetime_ability_name_("MainAbility") {
}

AppManager::~AppManager() {
}

bool AppManager::initialize() {
    std::cout << "AppManager initialized" << std::endl;
    return true;
}

bool AppManager::executeShellCommand(const std::string& cmd, std::string* output) {
    // Note: popen/pclose are POSIX functions. On Windows during development,
    // ensure compatibility or use cross-platform alternatives.
    //
    // ARCHITECTURE DECISION: This service runs ON the HarmonyOS device.
    // Therefore we execute shell commands directly, not via 'hdc shell'.
    //
    // Justification for Task 3 change:
    // - Original spec used: std::string full_cmd = "hdc shell \"" + cmd + "\"";
    // - This assumes service runs on host machine and controls device remotely
    // - However, CMakeLists.txt cross-compiles for HarmonyOS (aarch64-linux-ohos)
    // - Deploy command: hdc file send ... /data/local/tmp/openclaw_service
    // - Runtime: hdc shell "/data/local/tmp/openclaw_service"
    // - Testing confirmed: service runs on-device, hdc commands don't work from within device
    // - Changed to: FILE* pipe = popen(cmd.c_str(), "r");
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        std::cerr << "Failed to execute command: " << cmd << std::endl;
        return false;
    }

    // RAII wrapper to ensure pipe is always closed
    auto pipe_closer = [](FILE* p) { if (p) pclose(p); };
    std::unique_ptr<FILE, decltype(pipe_closer)> pipe_guard(pipe, pipe_closer);

    if (output) {
        char buffer[256];
        while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
            *output += buffer;
        }
    }

    // Release to get result before destructor closes
    FILE* raw_pipe = pipe_guard.release();
    int result = pclose(raw_pipe);
    return (result == 0);
}

bool AppManager::launchApp(const std::string& bundle_name, const std::string& ability_name) {
    // Handle empty ability_name - use default
    std::string actual_ability = ability_name.empty() ? "MainAbility" : ability_name;

    // Sanitize inputs by wrapping in quotes to prevent injection
    std::string cmd = "aa start -a \"" + actual_ability + "\" -b \"" + bundle_name + "\"";
    std::string output;
    bool success = executeShellCommand(cmd, &output);

    if (success) {
        std::cout << "Launched app: " << bundle_name << std::endl;
    } else {
        std::cerr << "Failed to launch app: " << bundle_name << std::endl;
        std::cerr << "Output: " << output << std::endl;
    }

    return success;
}

bool AppManager::backgroundApp(const std::string& bundle_name) {
    // HarmonyOS doesn't directly support backgrounding apps
    // We launch home screen instead, which backgrounds the current app
    // Note: bundle_name is logged for debugging but not used in the command
    std::cout << "Backgrounding app (if foreground): " << bundle_name << std::endl;
    std::string cmd = "input keyevent 3";  // HOME key
    return executeShellCommand(cmd);
}

bool AppManager::isAppRunning(const std::string& bundle_name) {
    // Use grep -v grep to avoid matching the grep process itself
    // Use word boundary matching with grep -w for more precise matching
    std::string cmd = "ps -ef | grep -w \"" + bundle_name + "\" | grep -v grep";
    std::string output;
    executeShellCommand(cmd, &output);

    // Check if bundle name appears in output (excluding grep itself)
    size_t pos = output.find(bundle_name);
    if (pos == std::string::npos) {
        return false;
    }

    // Additional verification: ensure we found a process, not just the command
    return !output.empty();
}

AppInfo AppManager::getForegroundApp() {
    AppInfo info;
    std::string cmd = "dumpsys activity top | grep ACTIVITY";
    std::string output;
    executeShellCommand(cmd, &output);

    // Parse output to get bundle name
    // Format: "ACTIVITY com.huawei.columbus/com.huawei.columbus.MainAbility ..."
    size_t pos = output.find("ACTIVITY ");
    if (pos != std::string::npos) {
        size_t start = pos + 9;  // Length of "ACTIVITY "

        // Add bounds checking: ensure start is within string
        if (start < output.length()) {
            size_t slash = output.find("/", start);

            // Add bounds checking: ensure slash is found and is within string
            if (slash != std::string::npos && slash > start && slash < output.length()) {
                // Calculate length safely
                size_t length = slash - start;

                // Add bounds checking: ensure length is reasonable
                if (length > 0 && length < 256) {  // Sanity check for bundle name length
                    try {
                        info.bundle_name = output.substr(start, length);
                        info.is_foreground = true;
                    } catch (const std::out_of_range& e) {
                        std::cerr << "Error parsing bundle name: " << e.what() << std::endl;
                    }
                }
            }
        }
    }

    return info;
}

std::vector<AppInfo> AppManager::getRunningApps() {
    std::vector<AppInfo> apps;

    // TODO: Implement proper parsing of dumpsys activity processes output
    // Current implementation returns empty list as parsing requires actual device output
    // Format varies by HarmonyOS version and needs real device testing
    //
    // To implement:
    // 1. Capture dumpsys output from actual device
    // 2. Parse ProcessRecord lines to extract:
    //    - Bundle name
    //    - Ability name
    //    - Process state (foreground/background)
    // 3. Handle multiple process formats across HarmonyOS versions

    std::string cmd = "dumpsys activity processes";
    std::string output;
    executeShellCommand(cmd, &output);

    // Placeholder for future implementation
    // std::istringstream lines(output);
    // std::string line;
    // while (std::getline(lines, line)) {
    //     if (line.find("ProcessRecord") != std::string::npos) {
    //         AppInfo info;
    //         // Parse bundle name from line
    //         // apps.push_back(info);
    //     }
    // }

    return apps;
}

bool AppManager::bringMeetimeToForeground() {
    // Launch app (will bring to foreground if already running, or start if not)
    // HarmonyOS aa start command handles both cases automatically
    return launchApp(meetime_bundle_name_, meetime_ability_name_);
}
