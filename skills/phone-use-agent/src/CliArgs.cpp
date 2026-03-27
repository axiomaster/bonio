#include "CliArgs.h"
#include "ExitCodes.h"
#include "Config.h"
#include <iostream>
#include <cstring>

CliArgs CliParser::parse(int argc, char** argv) {
    CliArgs args;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];

        if (arg == "--help" || arg == "-h") {
            args.show_help = true;
            args.valid = true;
            return args;
        }

        if (arg == "--version" || arg == "-v") {
            args.show_version = true;
            args.valid = true;
            return args;
        }

        if (arg == "--apikey") {
            if (i + 1 >= argc || argv[i + 1][0] == '-') {
                args.error_message = "Option --apikey requires a value";
                args.valid = false;
                return args;
            }
            args.apikey = argv[++i];
        } else if (arg == "--task") {
            if (i + 1 >= argc || argv[i + 1][0] == '-') {
                args.error_message = "Option --task requires a value";
                args.valid = false;
                return args;
            }
            args.task = argv[++i];
        } else if (arg == "--timeout") {
            if (i + 1 >= argc || argv[i + 1][0] == '-') {
                args.error_message = "Option --timeout requires a numeric value";
                args.valid = false;
                return args;
            }
            try {
                int timeout = std::stoi(argv[++i]);
                if (timeout <= 0) {
                    args.error_message = "Timeout must be a positive number";
                    args.valid = false;
                    return args;
                }
                args.timeout_seconds = timeout;
            } catch (const std::exception& e) {
                args.error_message = "Invalid timeout value: " + std::string(argv[i]);
                args.valid = false;
                return args;
            }
        } else if (arg == "--verbose") {
            args.verbose = true;
        } else if (arg == "--max-step") {
            if (i + 1 >= argc || argv[i + 1][0] == '-') {
                args.error_message = "Option --max-step requires a numeric value";
                args.valid = false;
                return args;
            }
            try {
                int max_step = std::stoi(argv[++i]);
                if (max_step <= 0 || max_step > 200) {
                    args.error_message = "Max step must be between 1 and 200";
                    args.valid = false;
                    return args;
                }
                args.max_step = max_step;
            } catch (const std::exception& e) {
                args.error_message = "Invalid max-step value: " + std::string(argv[i]);
                args.valid = false;
                return args;
            }
        } else if (arg.substr(0, 2) == "--") {
            args.error_message = "Unknown option: " + arg;
            args.valid = false;
            return args;
        }
    }

    // Validate required arguments
    // Note: apikey is optional here - can be loaded from config file
    // Only task is required on command line
    if (args.task.empty()) {
        args.error_message = "Missing required argument: --task";
        args.valid = false;
        return args;
    }

    args.valid = true;
    return args;
}

void CliParser::printHelp() {
    std::cout << "phone-use-harmonyos - HarmonyOS AI Agent CLI\n"
              << "\n"
              << "USAGE:\n"
              << "    phone-use-harmonyos --task <command> [OPTIONS]\n"
              << "\n"
              << "ARGUMENTS:\n"
              << "    --task <COMMAND>        Task description in Chinese (required)\n"
              << "\n"
              << "OPTIONS:\n"
              << "    --apikey <API_KEY>      GLM API key (optional if set in config)\n"
              << "    --max-step <NUM>        Maximum execution steps [default: 20, max: 200]\n"
              << "    --verbose               Enable verbose output\n"
              << "    --help, -h              Show this help message\n"
              << "    --version               Show version\n"
              << "\n"
              << "CONFIG:\n"
              << "    Config file: /data/local/.phone-use-harmonyos/phone-use-harmonyos.conf\n"
              << "    API key can be set in config file if not provided via --apikey\n"
              << "\n"
              << "EXAMPLES:\n"
              << "    phone-use-harmonyos --task \"打开美团搜索附近的火锅店\"\n"
              << "    phone-use-harmonyos --task \"打开微信\" --verbose\n"
              << "    phone-use-harmonyos --task \"复杂多步骤任务\" --max-step 60\n"
              << "\n"
              << "EXIT CODES:\n"
              << "    0   Success\n"
              << "    1   General failure\n"
              << "    2   Invalid arguments\n"
              << "    4   Task execution failed\n"
              << "    5   Timeout (exceeded max steps)\n"
              << "    10  Network error\n"
              << "    11  Initialization failed\n"
              << std::endl;
}

void CliParser::printVersion() {
    std::cout << "phone-use-harmonyos version " << VERSION << std::endl;
}
