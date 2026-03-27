#include "AndroidPlatform.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <memory>
#include <cstdio>
#include <thread>
#include <chrono>
#include <regex>

#include <dlfcn.h>

// libcurl constants (since we load dynamically)
#define CURLOPT_URL 10002
#define CURLOPT_POSTFIELDS 10015
#define CURLOPT_POSTFIELDSIZE 10016
#define CURLOPT_CUSTOMREQUEST 10036
#define CURLOPT_HTTPHEADER 10023
#define CURLOPT_WRITEFUNCTION 20011
#define CURLOPT_WRITEDATA 10001
#define CURLOPT_TIMEOUT 10013
#define CURLINFO_RESPONSE_CODE 0x100002
#define CURL_GLOBAL_ALL 3

// Android HTTP client implementation (uses libcurl)
class AndroidHttpClient : public IHttpClient {
public:
    AndroidHttpClient() : timeout_seconds_(30), initialized_(false), curl_handle_(nullptr) {}
    ~AndroidHttpClient() override {
        if (curl_handle_) {
            if (g_curl.handle && g_curl.easy_cleanup) {
                g_curl.easy_cleanup(curl_handle_);
            }
        }
    }

    bool initialize() override {
        if (initialized_) return true;
        if (!g_curl.load()) {
            std::cerr << "[AndroidHttpClient] Failed to load libcurl" << std::endl;
            return false;
        }
        g_curl.global_init(3); // CURL_GLOBAL_ALL
        initialized_ = true;
        return true;
    }

    void setTimeout(int seconds) override { timeout_seconds_ = seconds; }

    Response post(const std::string& url,
                 const std::string& json_body,
                 const std::map<std::string, std::string>& headers) override {
        Response response;
        if (!initialize()) {
            response.error = "HttpClient libcurl initialization failed";
            return response;
        }

        CURL* curl = g_curl.easy_init();
        if (!curl) {
            response.error = "curl_easy_init failed";
            return response;
        }

        struct curl_slist* header_list = nullptr;
        for (const auto& h : headers) {
            std::string header_str = h.first + ": " + h.second;
            header_list = g_curl.slist_append(header_list, header_str.c_str());
        }

        g_curl.easy_setopt(curl, CURLOPT_URL, url.c_str());
        if (!json_body.empty()) {
            g_curl.easy_setopt(curl, CURLOPT_POSTFIELDS, json_body.c_str());
            g_curl.easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)json_body.length());
        } else {
            g_curl.easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "POST");
        }

        if (header_list) {
            g_curl.easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
        }

        g_curl.easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
        g_curl.easy_setopt(curl, CURLOPT_WRITEDATA, &response.body);
        g_curl.easy_setopt(curl, CURLOPT_TIMEOUT, (long)timeout_seconds_);

        int res = g_curl.easy_perform(curl);
        if (res != 0) {
            response.success = false;
            response.error = "curl_easy_perform failed with code " + std::to_string(res);
        } else {
            long response_code = 0;
            g_curl.easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
            response.status_code = (int)response_code;
            response.success = (response.status_code >= 200 && response.status_code < 300);
        }

        if (header_list) g_curl.slist_free_all(header_list);
        g_curl.easy_cleanup(curl);

        return response;
    }

    Response get(const std::string& url,
                const std::map<std::string, std::string>& headers) override {
        Response response;
        if (!initialize()) {
            response.error = "HttpClient libcurl initialization failed";
            return response;
        }

        CURL* curl = g_curl.easy_init();
        if (!curl) {
            response.error = "curl_easy_init failed";
            return response;
        }

        struct curl_slist* header_list = nullptr;
        for (const auto& h : headers) {
            std::string header_str = h.first + ": " + h.second;
            header_list = g_curl.slist_append(header_list, header_str.c_str());
        }

        g_curl.easy_setopt(curl, CURLOPT_URL, url.c_str());
        if (header_list) {
            g_curl.easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
        }

        g_curl.easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
        g_curl.easy_setopt(curl, CURLOPT_WRITEDATA, &response.body);
        g_curl.easy_setopt(curl, CURLOPT_TIMEOUT, (long)timeout_seconds_);

        int res = g_curl.easy_perform(curl);
        if (res != 0) {
            response.success = false;
            response.error = "curl_easy_perform failed with code " + std::to_string(res);
        } else {
            long response_code = 0;
            g_curl.easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
            response.status_code = (int)response_code;
            response.success = (response.status_code >= 200 && response.status_code < 300);
        }

        if (header_list) g_curl.slist_free_all(header_list);
        g_curl.easy_cleanup(curl);

        return response;
    }

private:
    int timeout_seconds_;
    bool initialized_;
    void* curl_handle_;

    // libcurl types and function pointers
    typedef void CURL;
    struct curl_slist;
    typedef int (*curl_global_init_t)(long);
    typedef void (*curl_global_cleanup_t)();
    typedef CURL* (*curl_easy_init_t)();
    typedef int (*curl_easy_setopt_t)(CURL*, int, ...);
    typedef int (*curl_easy_perform_t)(CURL*);
    typedef void (*curl_easy_cleanup_t)(CURL*);
    typedef int (*curl_easy_getinfo_t)(CURL*, int, ...);
    typedef struct curl_slist* (*curl_slist_append_t)(struct curl_slist*, const char*);
    typedef void (*curl_slist_free_all_t)(struct curl_slist*);

    struct CurlApi {
        void* handle = nullptr;
        curl_global_init_t global_init;
        curl_global_cleanup_t global_cleanup;
        curl_easy_init_t easy_init;
        curl_easy_setopt_t easy_setopt;
        curl_easy_perform_t easy_perform;
        curl_easy_cleanup_t easy_cleanup;
        curl_easy_getinfo_t easy_getinfo;
        curl_slist_append_t slist_append;
        curl_slist_free_all_t slist_free_all;

        bool load() {
            if (handle) return true;

            // Android libcurl paths
            const char* paths[] = {
                "libcurl.so",
                "/system/lib64/libcurl.so",
                "/system/lib/libcurl.so",
                "/vendor/lib64/libcurl.so",
                "/vendor/lib/libcurl.so",
                "/data/local/tmp/libcurl.so"
            };

            for (const char* path : paths) {
                handle = dlopen(path, RTLD_LAZY);
                if (handle) {
                    printf("[AndroidHttpClient] Loaded libcurl from %s\n", path);
                    break;
                }
            }

            if (!handle) {
                printf("[AndroidHttpClient] Failed to load libcurl: %s\n", dlerror());
                return false;
            }

#define LOAD_SYM(name) name = (curl_##name##_t)dlsym(handle, "curl_" #name); \
            if (!name) { printf("[AndroidHttpClient] Missing curl_" #name "\n"); return false; }

            LOAD_SYM(global_init);
            LOAD_SYM(global_cleanup);
            LOAD_SYM(easy_init);
            LOAD_SYM(easy_setopt);
            LOAD_SYM(easy_perform);
            LOAD_SYM(easy_cleanup);
            LOAD_SYM(easy_getinfo);
            LOAD_SYM(slist_append);
            LOAD_SYM(slist_free_all);

            return true;
        }
    };

    static CurlApi g_curl;
    static size_t WriteCallback(void* contents, size_t size, size_t nmemb, void* userp) {
        size_t realsize = size * nmemb;
        std::string* body = static_cast<std::string*>(userp);
        body->append(static_cast<char*>(contents), realsize);
        return realsize;
    }
};

AndroidHttpClient::CurlApi AndroidHttpClient::g_curl;

// AndroidPlatform implementation
AndroidPlatform::AndroidPlatform() {
    detectScreenSize();
}

AndroidPlatform::~AndroidPlatform() {}

std::string AndroidPlatform::getDeviceId() const {
    if (!cached_device_id_.empty()) return cached_device_id_;

    std::string output;
    const_cast<AndroidPlatform*>(this)->executeCommand("getprop ro.serialno", &output);

    // Trim whitespace
    size_t start = output.find_first_not_of(" \n\r\t");
    size_t end = output.find_last_not_of(" \n\r\t");
    if (start != std::string::npos && end != std::string::npos) {
        cached_device_id_ = output.substr(start, end - start + 1);
    } else {
        cached_device_id_ = "unknown";
    }
    return cached_device_id_;
}

void AndroidPlatform::detectScreenSize() {
    std::string output;
    executeCommand("wm size", &output);

    // Parse "Physical size: 1080x2400" or "Override size: 1080x2400"
    std::regex size_regex(R"((?:Physical|Override)\s+size:\s*(\d+)x(\d+))");
    std::smatch match;
    if (std::regex_search(output, match, size_regex)) {
        screen_width_ = std::stoi(match[1].str());
        screen_height_ = std::stoi(match[2].str());
    } else {
        // Fallback defaults
        screen_width_ = 1080;
        screen_height_ = 2400;
    }
}

bool AndroidPlatform::takeScreenshot(const std::string& output_path, int width, int height) {
    // Android uses screencap command
    // screencap -p writes PNG format
    std::string cmd = "screencap -p " + output_path;

    if (!executeCommand(cmd)) {
        // Try alternative method
        cmd = "screencap " + output_path;
        if (!executeCommand(cmd)) {
            std::cerr << "Failed to take screenshot" << std::endl;
            return false;
        }
    }

    // Verify file exists
    std::ifstream file(output_path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        std::cerr << "Screenshot file not created: " << output_path << std::endl;
        return false;
    }

    std::streamsize file_size = file.tellg();
    file.close();

    if (file_size < 1000) {
        std::cerr << "Screenshot file too small: " << file_size << " bytes" << std::endl;
        return false;
    }

    std::cout << "Screenshot saved: " << output_path << " (" << file_size << " bytes)" << std::endl;
    return true;
}

bool AndroidPlatform::getScreenSize(int& width, int& height) {
    if (screen_width_ > 0 && screen_height_ > 0) {
        width = screen_width_;
        height = screen_height_;
        return true;
    }

    detectScreenSize();
    width = screen_width_;
    height = screen_height_;
    return true;
}

std::string AndroidPlatform::dumpUITree(const std::string& output_path) {
    // Android uses uiautomator dump
    std::string cmd = "uiautomator dump " + output_path + " > /dev/null 2>&1";

    if (!executeCommand(cmd)) {
        // Try without redirect to see error
        std::string error;
        executeCommand("uiautomator dump " + output_path, &error);
        std::cerr << "uiautomator dump failed: " << error << std::endl;
        return "{}";
    }

    // Read the XML file
    std::ifstream file(output_path);
    if (!file.is_open()) {
        // Try default location
        std::ifstream default_file("/sdcard/window_dump.xml");
        if (default_file.is_open()) {
            std::string content((std::istreambuf_iterator<char>(default_file)),
                               std::istreambuf_iterator<char>());
            return content;
        }
        std::cerr << "Failed to open UI tree file: " << output_path << std::endl;
        return "{}";
    }

    std::string content((std::istreambuf_iterator<char>(file)),
                        std::istreambuf_iterator<char>());
    return content;
}

bool AndroidPlatform::tap(int x, int y) {
    std::string cmd = "input tap " + std::to_string(x) + " " + std::to_string(y);
    return executeCommand(cmd);
}

bool AndroidPlatform::swipe(int x1, int y1, int x2, int y2, int duration_ms) {
    std::string cmd = "input swipe " +
                     std::to_string(x1) + " " + std::to_string(y1) + " " +
                     std::to_string(x2) + " " + std::to_string(y2) + " " +
                     std::to_string(duration_ms);
    return executeCommand(cmd);
}

bool AndroidPlatform::longPress(int x, int y) {
    // Android: input swipe with same start/end point and long duration
    std::string cmd = "input swipe " +
                     std::to_string(x) + " " + std::to_string(y) + " " +
                     std::to_string(x) + " " + std::to_string(y) + " 500";
    return executeCommand(cmd);
}

bool AndroidPlatform::doubleTap(int x, int y) {
    // Android doesn't have native double-tap, simulate with two quick taps
    tap(x, y);
    sleepMs(100);
    return tap(x, y);
}

bool AndroidPlatform::inputText(const std::string& text) {
    // Escape spaces and special characters for shell
    std::string escaped;
    for (char c : text) {
        switch (c) {
            case ' ': escaped += "%s"; break;
            case '&': escaped += "\\&"; break;
            case '|': escaped += "\\|"; break;
            case ';': escaped += "\\;"; break;
            case '(': escaped += "\\("; break;
            case ')': escaped += "\\)"; break;
            case '<': escaped += "\\<"; break;
            case '>': escaped += "\\>"; break;
            default: escaped += c;
        }
    }

    std::string cmd = "input text \"" + escaped + "\"";
    return executeCommand(cmd);
}

bool AndroidPlatform::pressBack() {
    return executeCommand("input keyevent KEYCODE_BACK");
}

bool AndroidPlatform::pressHome() {
    return executeCommand("input keyevent KEYCODE_HOME");
}

bool AndroidPlatform::pressKey(int keycode) {
    std::string cmd = "input keyevent " + std::to_string(keycode);
    return executeCommand(cmd);
}

bool AndroidPlatform::launchApp(const std::string& package_name, const std::string& activity_name) {
    std::string cmd;
    if (activity_name.empty()) {
        // Try to launch with just package name (monkey)
        cmd = "monkey -p " + package_name + " -c android.intent.category.LAUNCHER 1";
    } else {
        // Launch specific activity
        cmd = "am start -n " + package_name + "/" + activity_name;
    }

    std::string output;
    bool success = executeCommand(cmd, &output);

    if (success) {
        std::cout << "Launched app: " << package_name << std::endl;
    } else {
        std::cerr << "Failed to launch app: " << package_name << std::endl;
        std::cerr << "Output: " << output << std::endl;
    }

    return success;
}

AppInfo AndroidPlatform::getForegroundApp() {
    AppInfo info;
    std::string output;
    executeCommand("dumpsys activity activities | grep -E 'mResumedActivity|mFocusedApp'", &output);

    // Parse "mResumedActivity: ActivityRecord{... com.example.app/com.example.MainActivity ...}"
    std::regex activity_regex(R"(mResumedActivity:.*?\s+([a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+)/([a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)*))");
    std::smatch match;
    if (std::regex_search(output, match, activity_regex)) {
        info.package_name = match[1].str();
        info.main_activity = match[3].str();
        info.is_foreground = true;
    }

    return info;
}

std::vector<AppInfo> AndroidPlatform::getRunningApps() {
    std::vector<AppInfo> apps;
    std::string output;
    executeCommand("dumpsys activity processes | grep --color=never ProcessRecord", &output);

    // Parse process records
    std::regex proc_regex(R"(ProcessRecord\{[^\}]+\}\s+(\d+):([a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+)/)");
    auto words_begin = std::sregex_iterator(output.begin(), output.end(), proc_regex);
    auto words_end = std::sregex_iterator();

    for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
        std::smatch match = *i;
        AppInfo info;
        info.package_name = match[2].str();
        apps.push_back(info);
    }

    return apps;
}

bool AndroidPlatform::isAppRunning(const std::string& package_name) {
    std::string cmd = "pidof " + package_name;
    std::string output;
    executeCommand(cmd, &output);
    return !output.empty();
}

bool AndroidPlatform::executeCommand(const std::string& cmd, std::string* output) {
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        std::cerr << "Failed to execute command: " << cmd << std::endl;
        return false;
    }

    auto pipe_closer = [](FILE* p) { if (p) pclose(p); };
    std::unique_ptr<FILE, decltype(pipe_closer)> pipe_guard(pipe, pipe_closer);

    if (output) {
        char buffer[4096];
        while (fgets(buffer, sizeof(buffer), pipe_guard.get()) != nullptr) {
            *output += buffer;
        }
    }

    FILE* raw_pipe = pipe_guard.release();
    int result = pclose(raw_pipe);
    return (result == 0);
}

IHttpClient* AndroidPlatform::createHttpClient() {
    return new AndroidHttpClient();
}

void AndroidPlatform::sleepMs(int milliseconds) {
    std::this_thread::sleep_for(std::chrono::milliseconds(milliseconds));
}
