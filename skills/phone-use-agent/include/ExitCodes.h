#pragma once

namespace ExitCodes {
    constexpr int SUCCESS = 0;
    constexpr int GENERAL_FAILURE = 1;
    constexpr int INVALID_ARGS = 2;
    constexpr int API_AUTH_FAILED = 3;
    constexpr int TASK_FAILED = 4;
    constexpr int TIMEOUT = 5;
    constexpr int NETWORK_ERROR = 10;
    constexpr int INITIALIZATION_FAILED = 11;
    constexpr int SCREENSHOT_FAILED = 12;
}
