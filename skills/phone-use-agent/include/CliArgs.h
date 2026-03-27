#pragma once

#include <string>

struct CliArgs {
    std::string apikey;
    std::string task;
    int timeout_seconds = 30;
    int max_step = 20;  // Maximum number of steps (default: 20)
    bool verbose = false;
    bool show_help = false;
    bool show_version = false;
    bool valid = false;
    std::string error_message;
};

class CliParser {
public:
    static CliArgs parse(int argc, char** argv);
    static void printHelp();
    static void printVersion();
};
