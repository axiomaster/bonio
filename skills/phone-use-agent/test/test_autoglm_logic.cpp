#include "TaskExecutor.h"
#include "AutoGLMClient.h"
#include <iostream>
#include <cassert>
#include <vector>
#include <map>

// Mock UIInspector and AppManager are not needed if we mock the system calls or just test parsing
// For this unit test, we want to verify:
// 1. AutoGLMClient response parsing (Mocking HTTP response)
// 2. TaskExecutor action parsing

void test_response_parsing() {
    std::cout << "Testing AutoGLM Response Parsing..." << std::endl;
    
    // We can't easily test private methods of AutoGLMClient without friendship or public helpers
    // But we can test TaskExecutor::parseActionString if we make it public or friend
    // Let's rely on TaskExecutor's exposed behavior or use a "TestableTaskExecutor" subclass
}

class TestableTaskExecutor : public TaskExecutor {
public:
    using TaskExecutor::parseActionString;
    using TaskExecutor::ParsedAction;
};

void test_action_parsing() {
    std::cout << "Testing Action Parsing..." << std::endl;
    TestableTaskExecutor executor;
    
    // Test 1: Tap
    {
        auto action = executor.parseActionString("do(action=\"Tap\", element=[500,600])");
        assert(action.type == "Tap");
        assert(action.args["element"] == "500,600");
        std::cout << "  Tap [500,600] - PASS" << std::endl;
    }
    
    // Test 2: Type
    {
        auto action = executor.parseActionString("do(action=\"Type\", text=\"Hello World\")");
        assert(action.type == "Type");
        assert(action.args["text"] == "Hello World");
        std::cout << "  Type \"Hello World\" - PASS" << std::endl;
    }
    
    // Test 3: Swipe
    {
        auto action = executor.parseActionString("do(action=\"Swipe\", start=[100,100], end=[500,500])");
        assert(action.type == "Swipe");
        assert(action.args["start"] == "100,100");
        assert(action.args["end"] == "500,500");
        std::cout << "  Swipe [100,100]->[500,500] - PASS" << std::endl;
    }
    
    // Test 4: Finish
    {
        auto action = executor.parseActionString("finish(message=\"Task Complete\")");
        assert(action.type == "finish");
        assert(action.args["message"] == "Task Complete");
        std::cout << "  Finish \"Task Complete\" - PASS" << std::endl;
    }

    // Test 5: Mixed Quotes/Spaces
    {
        auto action = executor.parseActionString("do(action=\"Type\", text=\"Wait 5 seconds\")");
        assert(action.type == "Type");
        assert(action.args["text"] == "Wait 5 seconds");
        std::cout << "  Type with spaces - PASS" << std::endl;
    }
}

int main() {
    test_action_parsing();
    std::cout << "All tests passed!" << std::endl;
    return 0;
}
