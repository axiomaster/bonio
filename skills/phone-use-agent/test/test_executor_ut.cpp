#include "TaskExecutor.h"
#include <iostream>
#include <cassert>
#include <vector>
#include <string>

// Subclass to access protected methods
class TestableTaskExecutor : public TaskExecutor {
public:
    using TaskExecutor::parseActionString;
    using TaskExecutor::convertCoordinates;
    using TaskExecutor::ParsedAction;
};

void test_parsing() {
    std::cout << "Testing Parsing..." << std::endl;
    TestableTaskExecutor executor;

    // 1. Standard Tap with quotes
    {
        auto act = executor.parseActionString("do(action=\"Tap\", element=\"500,500\")");
        if (act.type != "Tap") std::cerr << "FAIL 1a: type=" << act.type << std::endl;
        if (act.args["element"] != "500,500") std::cerr << "FAIL 1b: element=" << act.args["element"] << std::endl;
        assert(act.type == "Tap");
        assert(act.args["element"] == "500,500");
    }

    // 2. Tap with brackets [x, y]
    {
        auto act = executor.parseActionString("do(action=\"Tap\", element=[500, 500])");
        if (act.type != "Tap") std::cerr << "FAIL 2a: type=" << act.type << std::endl;
        // Logic should remove spaces: "500,500"
        if (act.args["element"] != "500,500") std::cerr << "FAIL 2b: element=" << act.args["element"] << std::endl;
        assert(act.type == "Tap");
        assert(act.args["element"] == "500,500");
    }

    // 3. Swipe with brackets
    {
        auto act = executor.parseActionString("do(action=\"Swipe\", start=[100, 100], end=[800, 800])");
        assert(act.type == "Swipe");
        assert(act.args["start"] == "100,100");
        assert(act.args["end"] == "800,800");
    }

    // 4. Type command
    {
        auto act = executor.parseActionString("do(action=\"Type\", text=\"Hello World\")");
        assert(act.type == "Type");
        assert(act.args["text"] == "Hello World");
    }
    
    // 5. Complex spacing
    {
        auto act = executor.parseActionString("do(  action = \"Tap\" ,  element = [ 123 , 456 ] )");
        assert(act.type == "Tap");
        assert(act.args["element"] == "123,456");
    }

    std::cout << "Parsing functionality verified." << std::endl;
}

void test_coordinates() {
    std::cout << "Testing Coordinates..." << std::endl;
    TestableTaskExecutor executor;
    
    // Current hardcoded resolution: 1224 x 2700
    // Relative 1000, 1000 -> 1224, 2700
    
    {
        auto coords = executor.convertCoordinates(500, 500);
        std::cout << "500,500 -> " << coords.first << "," << coords.second << std::endl;
        assert(coords.first == 660);
        assert(coords.second == 1424);
    }
    
    {
        auto coords = executor.convertCoordinates(0, 0);
        assert(coords.first == 0);
        assert(coords.second == 0);
    }
    
    {
        auto coords = executor.convertCoordinates(1000, 1000);
        assert(coords.first == 1320);
        assert(coords.second == 2848);
    }
    
    std::cout << "Coordinate functionality verified." << std::endl;
}

int main() {
    try {
        test_parsing();
        test_coordinates();
        std::cout << "ALL UT PASSED" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "UT FAILED with exception: " << e.what() << std::endl;
        return 1;
    } catch (...) {
        std::cerr << "UT FAILED with unknown exception" << std::endl;
        return 1;
    }
    return 0;
}
