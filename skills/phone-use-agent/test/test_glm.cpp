#include <iostream>
#include <string>
#include <vector>
#include "AutoGLMClient.h"
#include "Config.h"

int main() {
    printf("--- START OF AUTO-GLM CLIENT TEST ---\n");
    
    // Initialize Config (might need to set environment variables or mock file)
    // For testing, we'll manually set the keys if needed, but AutoGLMClient loads from Config.
    
    AutoGLMClient client;
    if (!client.initialize()) {
        printf("ERROR: Failed to initialize AutoGLMClient\n");
        return 1;
    }

    std::string keys[] = {
        "YOU-API-KEY"
    };
    
    for (const std::string& api_key : keys) {
        printf("\n--- Testing Key: ...%s ---\n", api_key.substr(api_key.length() - 3).c_str());
        
        // We need to bypass Config for this specific test if we want to rotate keys manually
        // Since api_key_ is private in AutoGLMClient, we might need a test-only setter or just rely on Config.
        // For now, let's assume one of them is in config. 
        // OR we can modify HttpClient directly in a similar way if we want to test keys.
        
        AutoGLMRequest request;
        request.user_command = "Check my messages";
        // request.screenshot_path = "/data/local/tmp/test_screen.png"; // Optional
        
        // Simulate TaskExecutor loop style (historically)
        request.history.push_back(AutoGLMClient::createSystemMessage("You are a phone assistant."));
        request.history.push_back(AutoGLMClient::createUserMessage(request.user_command));

        AutoGLMResponse response = client.processCommand(request);
        
        if (response.success) {
            printf("Success!\n");
            printf("Thinking: %s\n", response.thinking.c_str());
            printf("Action: %s\n", response.action.c_str());
        } else {
            printf("Failed: %s\n", response.reasoning.c_str());
        }
    }

    printf("--- END OF AUTO-GLM CLIENT TEST ---\n");
    return 0;
}
