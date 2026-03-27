#include <iostream>
#include <string>
#include <map>
#include <cstdio>
#include "HttpClient.h"

int main() {
    printf("--- START OF NETWORK TEST ---\n");
    fflush(stdout);
    
    HttpClient client;
    printf("Initializing HttpClient...\n");
    fflush(stdout);
    
    if (!client.initialize()) {
        printf("ERROR: Failed to initialize HttpClient\n");
        return 1;
    }

    printf("Testing POST request to httpbin.org/post...\n");
    fflush(stdout);
    
    std::string url = "http://httpbin.org/post";
    std::string body = "{\"test\": \"payload\", \"message\": \"hello from cronet\"}";
    std::map<std::string, std::string> headers;
    headers["Content-Type"] = "application/json";

    HttpResponse response = client.post(url, body, headers);

    if (response.success) {
        printf("SUCCESS! Status code: %d\n", response.status_code);
        printf("Response Body: %s\n", response.body.c_str());
        
        if (response.body.find("\"test\": \"payload\"") != std::string::npos) {
            printf("VERIFIED: Request body correctly received by server.\n");
        } else {
            printf("FAILED: Request body NOT found in server response.\n");
        }
    } else {
        printf("FAILED! Error: %s (Status: %d)\n", response.error.c_str(), response.status_code);
        if (!response.body.empty()) {
             printf("Response Body: %s\n", response.body.c_str());
        }
    }

    printf("--- END OF NETWORK TEST ---\n");
    return 0;
}
