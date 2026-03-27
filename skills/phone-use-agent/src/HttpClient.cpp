#include "HttpClient.h"
#include <iostream>
#include <vector>
#include <string>
#include <map>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <thread>
#include <dlfcn.h>
#include <cstring>
#include <cstdio>

#define LOG_TAG "HttpClient"

// libcurl basic types
typedef void CURL;
typedef void* CURLcode;
struct curl_slist;

// libcurl constants (simplified for our needs)
#define CURLOPT_URL 10002
#define CURLOPT_POSTFIELDS 10015
#define CURLOPT_POSTFIELDSIZE 10060
#define CURLOPT_HTTPHEADER 10023
#define CURLOPT_WRITEFUNCTION 20011
#define CURLOPT_WRITEDATA 10001
#define CURLOPT_TIMEOUT 10013
#define CURLOPT_CUSTOMREQUEST 10036
#define CURLOPT_VERBOSE 10041
#define CURLINFO_RESPONSE_CODE 2097154

// libcurl function pointer types
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
        // Search in known locations
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

HttpClient::HttpClient() : timeout_seconds_(30), initialized_(false) {}
HttpClient::~HttpClient() {}

bool HttpClient::initialize() {
    if (initialized_) return true;
    if (!g_curl.load()) return false;
    g_curl.global_init(3); // CURL_GLOBAL_ALL
    initialized_ = true;
    return true;
}

void HttpClient::setTimeout(int seconds) { timeout_seconds_ = seconds; }

HttpResponse HttpClient::post(const std::string& url, 
                              const std::string& json_body, 
                              const std::map<std::string, std::string>& headers) {
    HttpResponse response;
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

    printf("[HttpClient] Performing libcurl POST to %s\n", url.c_str());
    int res = g_curl.easy_perform(curl);
    if (res != 0) {
        response.success = false;
        response.error = "curl_easy_perform failed with code " + std::to_string(res);
        printf("[HttpClient] libcurl Error: %d\n", res);
    } else {
        long response_code = 0;
        g_curl.easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
        response.status_code = (int)response_code;
        response.success = (response.status_code >= 200 && response.status_code < 300);
        printf("[HttpClient] libcurl POST Success, Status: %d\n", response.status_code);
    }

    if (header_list) g_curl.slist_free_all(header_list);
    g_curl.easy_cleanup(curl);
    
    return response;
}

HttpResponse HttpClient::get(const std::string& url, 
                              const std::map<std::string, std::string>& headers) {
    HttpResponse response;
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

    printf("[HttpClient] Performing libcurl GET to %s\n", url.c_str());
    int res = g_curl.easy_perform(curl);
    if (res != 0) {
        response.success = false;
        response.error = "curl_easy_perform failed with code " + std::to_string(res);
    } else {
        long response_code = 0;
        g_curl.easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
        response.status_code = (int)response_code;
        response.success = (response.status_code >= 200 && response.status_code < 300);
        printf("[HttpClient] libcurl GET Success, Status: %d\n", response.status_code);
    }

    if (header_list) g_curl.slist_free_all(header_list);
    g_curl.easy_cleanup(curl);
    
    return response;
}
