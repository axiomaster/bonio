#include "HarmonyOSPlatform.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <memory>
#include <cstdio>
#include <unistd.h>
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
#define CURLOPT_VERBOSE 10041
#define CURLINFO_RESPONSE_CODE 0x100002
#define CURL_GLOBAL_ALL 3
#define RTLD_LAZY 1

// HarmonyOS HTTP client implementation (uses libcurl from OHOS)
class HarmonyOSHttpClient : public IHttpClient {
public:
    HarmonyOSHttpClient() : timeout_seconds_(30), initialized_(false) {}
    ~HarmonyOSHttpClient() override {}

    bool initialize() override {
        if (initialized_) return true;
        if (!g_curl.load()) return false;
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
        g_curl.easy_setopt(curl, CURLOPT_VERBOSE, 1L);

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
            const char* paths[] = {
                "/system/lib64/platformsdk/libcurl_shared.z.so",
                "/system/lib64/chipset-sdk/libcurl_shared.z.so",
                "/system/lib64/chipset-pub-sdk/libcurl_shared.z.so"
            };

            for (const char* path : paths) {
                handle = dlopen(path, RTLD_LAZY);
                if (handle) {
                    printf("[HttpClient] Loaded libcurl from %s\n", path);
                    break;
                }
            }

            if (!handle) {
                printf("[HttpClient] Failed to load libcurl_shared.z.so: %s\n", dlerror());
                return false;
            }

#define LOAD_SYM(name) name = (curl_##name##_t)dlsym(handle, "curl_" #name); \
            if (!name) { printf("[HttpClient] Missing curl_" #name "\n"); return false; }

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

HarmonyOSHttpClient::CurlApi HarmonyOSHttpClient::g_curl;

// HarmonyOSPlatform implementation
HarmonyOSPlatform::HarmonyOSPlatform() {}
HarmonyOSPlatform::~HarmonyOSPlatform() {}

std::string HarmonyOSPlatform::getDeviceId() const {
    if (!cached_device_id_.empty()) return cached_device_id_;

    std::string output;
    const_cast<HarmonyOSPlatform*>(this)->executeCommand("getprop ro.serialno", &output);

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

bool HarmonyOSPlatform::takeScreenshot(const std::string& output_path, int width, int height) {
    // Default to 0.5x dimensions if not specified
    int w = width > 0 ? width : 660;
    int h = height > 0 ? height : 1424;

    std::string cmd = "snapshot_display -w " + std::to_string(w) +
                     " -h " + std::to_string(h) +
                     " -f " + output_path + " 2>&1";

    std::string output;
    if (!executeCommand(cmd, &output)) {
        std::cerr << "Failed to take screenshot: " << output << std::endl;
        return false;
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

bool HarmonyOSPlatform::getScreenSize(int& width, int& height) {
    // Try to get from system property
    std::string output;
    executeCommand("dumpsys window displays | grep init", &output);

    // Parse "init=1320x2848" format
    size_t pos = output.find("init=");
    if (pos != std::string::npos) {
        size_t x_pos = output.find('x', pos);
        if (x_pos != std::string::npos) {
            try {
                width = std::stoi(output.substr(pos + 5, x_pos - pos - 5));
                // Find end of height (space or newline)
                size_t end = output.find_first_of(" \n", x_pos + 1);
                if (end == std::string::npos) end = output.length();
                height = std::stoi(output.substr(x_pos + 1, end - x_pos - 1));
                return true;
            } catch (...) {}
        }
    }

    // Fallback to default
    width = 1320;
    height = 2848;
    return true;
}

std::string HarmonyOSPlatform::dumpUITree(const std::string& output_path) {
    std::string cmd = "/bin/uitest dumpLayout -p " + output_path + " > /dev/null 2>&1";

    if (!executeCommand(cmd)) {
        std::cerr << "uitest dumpLayout command failed" << std::endl;
        return "{}";
    }

    std::ifstream file(output_path);
    if (!file.is_open()) {
        std::cerr << "Failed to open UI tree file: " << output_path << std::endl;
        return "{}";
    }

    std::string content((std::istreambuf_iterator<char>(file)),
                        std::istreambuf_iterator<char>());
    return content;
}

bool HarmonyOSPlatform::tap(int x, int y) {
    std::string cmd = "/bin/uitest uiInput click " + std::to_string(x) + " " + std::to_string(y);
    return executeCommand(cmd);
}

bool HarmonyOSPlatform::swipe(int x1, int y1, int x2, int y2, int duration_ms) {
    std::string cmd = "/bin/uitest uiInput swipe " +
                     std::to_string(x1) + " " + std::to_string(y1) + " " +
                     std::to_string(x2) + " " + std::to_string(y2) + " " +
                     std::to_string(duration_ms);
    return executeCommand(cmd);
}

bool HarmonyOSPlatform::longPress(int x, int y) {
    std::string cmd = "/bin/uitest uiInput longClick " + std::to_string(x) + " " + std::to_string(y);
    return executeCommand(cmd);
}

bool HarmonyOSPlatform::doubleTap(int x, int y) {
    std::string cmd = "/bin/uitest uiInput doubleClick " + std::to_string(x) + " " + std::to_string(y);
    return executeCommand(cmd);
}

bool HarmonyOSPlatform::inputText(const std::string& text) {
    // Escape quotes
    std::string escaped = text;
    size_t pos = 0;
    while ((pos = escaped.find('"', pos)) != std::string::npos) {
        escaped.replace(pos, 1, "\\\"");
        pos += 2;
    }
    std::string cmd = "/bin/uitest uiInput text \"" + escaped + "\"";
    return executeCommand(cmd);
}

bool HarmonyOSPlatform::pressBack() {
    return executeCommand("/bin/uitest uiInput keyEvent Back");
}

bool HarmonyOSPlatform::pressHome() {
    return executeCommand("/bin/uitest uiInput keyEvent Home");
}

bool HarmonyOSPlatform::pressKey(int keycode) {
    // HarmonyOS uses key names, convert keycode to name if needed
    std::string cmd = "/bin/uitest uiInput keyEvent " + std::to_string(keycode);
    return executeCommand(cmd);
}

bool HarmonyOSPlatform::launchApp(const std::string& package_name, const std::string& activity_name) {
    std::string ability = activity_name.empty() ? "MainAbility" : activity_name;
    std::string cmd = "aa start -a \"" + ability + "\" -b \"" + package_name + "\"";
    return executeCommand(cmd);
}

AppInfo HarmonyOSPlatform::getForegroundApp() {
    AppInfo info;
    std::string output;
    executeCommand("dumpsys activity top | grep ACTIVITY", &output);

    size_t pos = output.find("ACTIVITY ");
    if (pos != std::string::npos) {
        size_t start = pos + 9;
        if (start < output.length()) {
            size_t slash = output.find("/", start);
            if (slash != std::string::npos && slash > start && slash < output.length()) {
                size_t length = slash - start;
                if (length > 0 && length < 256) {
                    info.package_name = output.substr(start, length);
                    info.is_foreground = true;
                }
            }
        }
    }
    return info;
}

std::vector<AppInfo> HarmonyOSPlatform::getRunningApps() {
    std::vector<AppInfo> apps;
    // TODO: Implement parsing of dumpsys activity processes
    return apps;
}

bool HarmonyOSPlatform::isAppRunning(const std::string& package_name) {
    std::string cmd = "ps -ef | grep -w \"" + package_name + "\" | grep -v grep";
    std::string output;
    executeCommand(cmd, &output);
    return output.find(package_name) != std::string::npos && !output.empty();
}

bool HarmonyOSPlatform::executeCommand(const std::string& cmd, std::string* output) {
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

IHttpClient* HarmonyOSPlatform::createHttpClient() {
    return new HarmonyOSHttpClient();
}

void HarmonyOSPlatform::sleepMs(int milliseconds) {
    usleep(milliseconds * 1000);  // musl libc requires usleep
}
