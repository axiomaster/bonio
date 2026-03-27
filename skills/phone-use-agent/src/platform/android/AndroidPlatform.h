#pragma once

#include "../platform/Platform.h"
#include <memory>

class AndroidHttpClient;

class AndroidPlatform : public IPlatform {
public:
    AndroidPlatform();
    ~AndroidPlatform() override;

    // Platform identification
    std::string getName() const override { return "Android"; }
    std::string getDeviceId() const override;

    // Screen operations
    bool takeScreenshot(const std::string& output_path, int width = 0, int height = 0) override;
    bool getScreenSize(int& width, int& height) override;

    // UI tree operations
    std::string dumpUITree(const std::string& output_path) override;

    // Input operations
    bool tap(int x, int y) override;
    bool swipe(int x1, int y1, int x2, int y2, int duration_ms) override;
    bool longPress(int x, int y) override;
    bool doubleTap(int x, int y) override;
    bool inputText(const std::string& text) override;
    bool pressBack() override;
    bool pressHome() override;
    bool pressKey(int keycode) override;

    // App operations
    bool launchApp(const std::string& package_name, const std::string& activity_name) override;
    AppInfo getForegroundApp() override;
    std::vector<AppInfo> getRunningApps() override;
    bool isAppRunning(const std::string& package_name) override;

    // Shell execution
    bool executeCommand(const std::string& cmd, std::string* output = nullptr) override;

    // HTTP client factory
    IHttpClient* createHttpClient() override;

    // Sleep
    void sleepMs(int milliseconds) override;

private:
    mutable std::string cached_device_id_;
    int screen_width_ = 0;
    int screen_height_ = 0;

    void detectScreenSize();
};
