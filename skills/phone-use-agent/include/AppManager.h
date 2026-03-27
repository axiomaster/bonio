#pragma once

#include <string>
#include <vector>

struct AppInfo {
    std::string bundle_name;
    std::string ability_name;
    bool is_foreground;
};

class AppManager {
public:
    AppManager();
    ~AppManager();

    // Initialize ability kit connection
    bool initialize();

    // Launch app to foreground
    bool launchApp(const std::string& bundle_name, const std::string& ability_name = "");

    // Bring app to background
    bool backgroundApp(const std::string& bundle_name);

    // Check if app is running
    bool isAppRunning(const std::string& bundle_name);

    // Get current foreground app
    AppInfo getForegroundApp();

    // Get list of running apps
    std::vector<AppInfo> getRunningApps();

    // Specific for Meetime app
    // Bring Meetime app to foreground
    bool bringMeetimeToForeground();

    // Restart Meetime app
    bool restartMeetime();

    // Allow test code access to bundle name
    const std::string& getMeetimeBundleName() const { return meetime_bundle_name_; }

private:
    bool executeShellCommand(const std::string& cmd, std::string* output = nullptr);

    std::string meetime_bundle_name_;
    std::string meetime_ability_name_;
};
