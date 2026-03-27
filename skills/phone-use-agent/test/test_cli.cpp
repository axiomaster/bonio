#include <iostream>
#include <cassert>
#include <cstring>
#include "CliArgs.h"
#include "ExitCodes.h"

void test_help_flag() {
    char* argv[] = {(char*)"phone-use-harmonyos", (char*)"--help"};
    CliArgs args = CliParser::parse(2, argv);

    assert(args.show_help == true);
    assert(args.valid == true);
    std::cout << "PASS: test_help_flag" << std::endl;
}

void test_missing_apikey() {
    char* argv[] = {(char*)"phone-use-harmonyos", (char*)"--task", (char*)"test"};
    CliArgs args = CliParser::parse(3, argv);

    assert(args.valid == false);
    assert(args.error_message.find("apikey") != std::string::npos);
    std::cout << "PASS: test_missing_apikey" << std::endl;
}

void test_missing_task() {
    char* argv[] = {(char*)"phone-use-harmonyos", (char*)"--apikey", (char*)"sk-test"};
    CliArgs args = CliParser::parse(3, argv);

    assert(args.valid == false);
    assert(args.error_message.find("task") != std::string::npos);
    std::cout << "PASS: test_missing_task" << std::endl;
}

void test_valid_args() {
    char* argv[] = {
        (char*)"phone-use-harmonyos",
        (char*)"--apikey", (char*)"sk-test123",
        (char*)"--task", (char*)"打开微信",
        (char*)"--timeout", (char*)"60",
        (char*)"--verbose"
    };
    CliArgs args = CliParser::parse(8, argv);

    assert(args.valid == true);
    assert(args.apikey == "sk-test123");
    assert(args.task == "打开微信");
    assert(args.timeout_seconds == 60);
    assert(args.verbose == true);
    std::cout << "PASS: test_valid_args" << std::endl;
}

void test_unknown_option() {
    char* argv[] = {
        (char*)"phone-use-harmonyos",
        (char*)"--apikey", (char*)"sk-test",
        (char*)"--task", (char*)"test",
        (char*)"--unknown"
    };
    CliArgs args = CliParser::parse(6, argv);

    assert(args.valid == false);
    assert(args.error_message.find("Unknown") != std::string::npos);
    std::cout << "PASS: test_unknown_option" << std::endl;
}

void test_exit_codes() {
    assert(ExitCodes::SUCCESS == 0);
    assert(ExitCodes::INVALID_ARGS == 2);
    assert(ExitCodes::TASK_FAILED == 4);
    assert(ExitCodes::TIMEOUT == 5);
    std::cout << "PASS: test_exit_codes" << std::endl;
}

int main() {
    std::cout << "Running CLI tests..." << std::endl;

    test_help_flag();
    test_missing_apikey();
    test_missing_task();
    test_valid_args();
    test_unknown_option();
    test_exit_codes();

    std::cout << "\nAll CLI tests passed!" << std::endl;
    return 0;
}
