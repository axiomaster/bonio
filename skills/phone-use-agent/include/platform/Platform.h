#pragma once

#include <string>
#include <memory>
#include <vector>
#include <map>

// UI State information
struct UIState {
    std::string screenshot_path;
    std::string ui_tree_json;
    int screen_width = 0;
    int screen_height = 0;
};

// App information
struct AppInfo {
    std::string package_name;    // Android: package name, HarmonyOS: bundle name
    std::string main_activity;   // Android: activity, HarmonyOS: ability
    std::string display_name;
    bool is_foreground = false;
};

// Platform interface - abstract base class for platform-specific operations
class IPlatform {
public:
    virtual ~IPlatform() = default;

    // Platform identification
    virtual std::string getName() const = 0;
    virtual std::string getDeviceId() const = 0;

    // Screen operations
    virtual bool takeScreenshot(const std::string& output_path, int width = 0, int height = 0) = 0;
    virtual bool getScreenSize(int& width, int& height) = 0;

    // UI tree operations
    virtual std::string dumpUITree(const std::string& output_path) = 0;

    // Input operations
    virtual bool tap(int x, int y) = 0;
    virtual bool swipe(int x1, int y1, int x2, int y2, int duration_ms) = 0;
    virtual bool longPress(int x, int y) = 0;
    virtual bool doubleTap(int x, int y) = 0;
    virtual bool inputText(const std::string& text) = 0;
    virtual bool pressBack() = 0;
    virtual bool pressHome() = 0;
    virtual bool pressKey(int keycode) = 0;

    // App operations
    virtual bool launchApp(const std::string& package_name, const std::string& activity_name) = 0;
    virtual AppInfo getForegroundApp() = 0;
    virtual std::vector<AppInfo> getRunningApps() = 0;
    virtual bool isAppRunning(const std::string& package_name) = 0;

    // Shell execution
    virtual bool executeCommand(const std::string& cmd, std::string* output = nullptr) = 0;

    // HTTP client factory
    virtual class IHttpClient* createHttpClient() = 0;

    // Sleep (platform-specific implementation)
    virtual void sleepMs(int milliseconds) = 0;
};

// HTTP client interface
class IHttpClient {
public:
    virtual ~IHttpClient() = default;

    virtual bool initialize() = 0;
    virtual void setTimeout(int seconds) = 0;

    struct Response {
        int status_code = 0;
        std::string body;
        std::string error;
        bool success = false;
    };

    virtual Response post(const std::string& url,
                         const std::string& json_body,
                         const std::map<std::string, std::string>& headers) = 0;

    virtual Response get(const std::string& url,
                        const std::map<std::string, std::string>& headers) = 0;
};

// Platform factory
namespace PlatformFactory {
    std::unique_ptr<IPlatform> create();
    std::unique_ptr<IPlatform> createHarmonyOS();
    std::unique_ptr<IPlatform> createAndroid();
}
