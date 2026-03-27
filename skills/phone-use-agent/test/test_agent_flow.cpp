#include <iostream>
#include <thread>
#include <chrono>
#include "TaskExecutor.h"
#include "ConfigManager.h"

// Simple integration test for Task Executor flow
int main() {
    std::cout << "=== Agent Flow Integration Test ===" << std::endl;

    // Initialize components
    auto ui_inspector = std::make_shared<UIInspector>();
    auto app_manager = std::make_shared<AppManager>();

    // Initialize them
    if (!ui_inspector->initialize() || !app_manager->initialize()) {
        std::cerr << "Failed to initialize components" << std::endl;
        return 1;
    }

    // Create TaskExecutor with components
    TaskExecutor executor(ui_inspector, app_manager);
    if (!executor.initialize()) {
        std::cerr << "Failed to initialize TaskExecutor" << std::endl;
        return 1;
    }

    std::cout << "Initialization successful." << std::endl;

    // Simulate inputs
    std::string command = "Test Agent Flow";
    std::string screenshot = "/data/local/tmp/test_flow_screen.png"; // Placeholder
    std::string ui_tree = "{}"; // Placeholder

    // Create dummy screenshot file if needed (TaskExecutor reads it?)
    // Actually TaskExecutor reads the *result*, but AutoGLM reads the input.
    // In test mode, AutoGLM won't read the file, so it's fine if it doesn't exist.

    // Execute Task
    std::cout << "Executing task: " << command << std::endl;
    Task task = executor.executeTask(command, screenshot, ui_tree);

    // Verify Result
    if (task.status == TaskStatus::Completed) {
        std::cout << "Task completed successfully!" << std::endl;
        std::cout << "  Task ID: " << task.task_id << std::endl;
        std::cout << "  Action Plan: " << task.glm_response.action_plan << std::endl;

    } else {
        std::cerr << "Task failed: " << task.error_message << std::endl;
        return 1;
    }

    return 0;
}
