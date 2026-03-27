#include <iostream>
#include <memory>
#include <csignal>
#include <atomic>
#include "Config.h"
#include "ConfigManager.h"
#include "CliArgs.h"
#include "ExitCodes.h"
#include "core/TaskExecutor.h"
#include "platform/Platform.h"

// Global interruption flag
std::atomic<bool> g_interrupted(false);

void signalHandler(int signal) {
    std::cout << "\nInterrupt received, stopping..." << std::endl;
    g_interrupted = true;
}

int main(int argc, char** argv) {
    // Parse CLI arguments
    CliArgs args = CliParser::parse(argc, argv);

    // Handle --help
    if (args.show_help) {
        CliParser::printHelp();
        return ExitCodes::SUCCESS;
    }

    // Handle --version
    if (args.show_version) {
        CliParser::printVersion();
        return ExitCodes::SUCCESS;
    }

    // Handle invalid arguments
    if (!args.valid) {
        std::cerr << "Error: " << args.error_message << std::endl;
        std::cerr << "Use --help for usage information." << std::endl;
        return ExitCodes::INVALID_ARGS;
    }

    // Load config from file first (may contain API key)
    Config::getInstance().loadFromFile();

    // Set API key from command line if provided
    if (!args.apikey.empty()) {
        Config::getInstance().setApiKey(args.apikey);
        if (args.verbose) {
            std::cout << "[VERBOSE] API Key (from CLI): " << args.apikey.substr(0, 8) << "..." << std::endl;
        }
    } else {
        // API key not provided via CLI, check config file
        std::string config_api_key = Config::getInstance().getGlmApiKey();
        if (config_api_key.empty() || config_api_key == "YOUR_API_KEY_HERE") {
            std::cerr << "Error: No API key provided." << std::endl;
            std::cerr << "Please either:" << std::endl;
            std::cerr << "  1. Use --apikey YOUR_KEY" << std::endl;
            std::cerr << "  2. Or set glm_api_key in " << DEFAULT_CONFIG_PATH << std::endl;
            return ExitCodes::INVALID_ARGS;
        }
        if (args.verbose) {
            std::cout << "[VERBOSE] API Key (from config): " << config_api_key.substr(0, 8) << "..." << std::endl;
        }
    }

    if (args.verbose) {
        std::cout << "[VERBOSE] Task: " << args.task << std::endl;
    }

    // Setup signal handler
    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);

    // Create platform instance
    if (args.verbose) std::cout << "[VERBOSE] Creating platform instance..." << std::endl;
    auto platform = PlatformFactory::create();
    if (!platform) {
        std::cerr << "Error: Failed to create platform instance" << std::endl;
        return ExitCodes::INITIALIZATION_FAILED;
    }

    std::cout << "Platform: " << platform->getName() << std::endl;
    std::cout << "Device ID: " << platform->getDeviceId() << std::endl;

    // Initialize TaskExecutor with platform
    if (args.verbose) std::cout << "[VERBOSE] Initializing TaskExecutor..." << std::endl;
    auto task_executor = std::make_unique<TaskExecutor>(std::move(platform));

    if (!task_executor->initialize()) {
        std::cerr << "Error: Failed to initialize TaskExecutor" << std::endl;
        return ExitCodes::INITIALIZATION_FAILED;
    }

    // Set max step limit
    task_executor->setMaxStepLimit(args.max_step);
    if (args.verbose) {
        std::cout << "[VERBOSE] Max step limit: " << args.max_step << std::endl;
    }

    // Execute task
    std::cout << "\n========================================" << std::endl;
    std::cout << "Executing task: " << args.task << std::endl;
    std::cout << "Press Ctrl+C to interrupt..." << std::endl;
    std::cout << "========================================\n" << std::endl;

    Task task = task_executor->executeTask(args.task);

    // Determine exit code based on task status
    int exit_code;
    switch (task.status) {
        case TaskStatus::Completed:
            std::cout << "\nTask completed successfully" << std::endl;
            if (!task.result_screenshot_path.empty()) {
                std::cout << "Result screenshot: " << task.result_screenshot_path << std::endl;
            }
            exit_code = ExitCodes::SUCCESS;
            break;

        case TaskStatus::Interrupted:
            std::cerr << "Task interrupted by user" << std::endl;
            exit_code = ExitCodes::GENERAL_FAILURE;
            break;

        case TaskStatus::Failed:
            std::cerr << "Task failed: " << task.error_message << std::endl;

            // Determine specific failure type
            if (task.error_message.find("timeout") != std::string::npos ||
                task.error_message.find("step limit") != std::string::npos) {
                exit_code = ExitCodes::TIMEOUT;
            } else if (task.error_message.find("network") != std::string::npos ||
                       task.error_message.find("HTTP") != std::string::npos) {
                exit_code = ExitCodes::NETWORK_ERROR;
            } else {
                exit_code = ExitCodes::TASK_FAILED;
            }
            break;

        default:
            std::cerr << "Task ended with unknown status" << std::endl;
            exit_code = ExitCodes::GENERAL_FAILURE;
    }

    if (args.verbose) {
        std::cout << "[VERBOSE] Task ID: " << task.task_id << std::endl;
        std::cout << "[VERBOSE] Steps: " << task.step_count << std::endl;
        std::cout << "[VERBOSE] Exit code: " << exit_code << std::endl;
    }

    return exit_code;
}
