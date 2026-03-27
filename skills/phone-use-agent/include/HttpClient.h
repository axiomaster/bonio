#pragma once

#include <string>
#include <map>
#include <memory>
#include <mutex>
#include <condition_variable>

// Forward declaration for HarmonyOS HTTP type
struct Http_Response;

struct HttpResponse {
    int status_code;
    std::string body;
    std::string error;
    bool success;

    HttpResponse() : status_code(0), success(false) {}
};

class HttpClient {
public:
    HttpClient();
    ~HttpClient();

    // Initialize HTTP client
    bool initialize();

    // Perform POST request with JSON body
    HttpResponse post(const std::string& url,
                     const std::string& json_body,
                     const std::map<std::string, std::string>& headers);

    // Perform GET request
    HttpResponse get(const std::string& url,
                    const std::map<std::string, std::string>& headers);

    // Set timeout in seconds
    void setTimeout(int seconds);

private:
    int timeout_seconds_;
    bool initialized_;

    // Instance-scoped callback state (fixes Issue 1: Global state race condition)
    std::mutex callback_mutex_;
    std::condition_variable callback_cv_;
    HttpResponse* current_response_;
    bool request_completed_;

    // Helper method to perform HTTP request
    bool performRequest(const std::string& method,
                       const std::string& url,
                       const std::string& body,
                       const std::map<std::string, std::string>& headers,
                       HttpResponse& response);

    // Instance callback method
    void HttpCallback(Http_Response* httpResponse, uint32_t errCode);
};
