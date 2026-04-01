cmake_minimum_required(VERSION 3.16)
project(hiclaw VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)

# Enable LTO (Link Time Optimization) for smaller binary size and better performance
option(HICLAW_ENABLE_LTO "Enable Link Time Optimization" ON)
if(HICLAW_ENABLE_LTO AND NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
  # Try to enable interprocedural optimization (works on most compilers)
  set(CMAKE_INTERPROCEDURAL_OPTIMIZATIONS ON)
endif()

# Gateway backend: "websocketpp" | "libwebsockets" | "auto"
# HarmonyOS (OHOS) builds prefer websocketpp; host can use either.
set(HICLAW_GATEWAY_BACKEND "auto" CACHE STRING "Gateway WebSocket backend: websocketpp, libwebsockets, or auto")

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(LibWebSockets QUIET)

# ---- choose gateway backend (HarmonyOS first: prefer websocketpp) ----
set(HICLAW_USE_WEBSOCKETPP OFF)
set(HICLAW_USE_LIBWEBSOCKETS OFF)
if(HICLAW_GATEWAY_BACKEND STREQUAL "websocketpp")
  set(HICLAW_USE_WEBSOCKETPP ON)
elseif(HICLAW_GATEWAY_BACKEND STREQUAL "libwebsockets" AND LibWebSockets_FOUND)
  set(HICLAW_USE_LIBWEBSOCKETS ON)
elseif(HICLAW_GATEWAY_BACKEND STREQUAL "auto")
  if(CMAKE_SYSTEM_NAME STREQUAL "OHOS")
    set(HICLAW_USE_WEBSOCKETPP ON)
    message(STATUS "HiClaw gateway: using websocketpp (HarmonyOS default)")
  elseif(LibWebSockets_FOUND)
    set(HICLAW_USE_LIBWEBSOCKETS ON)
    message(STATUS "HiClaw gateway: using libwebsockets (auto)")
  else()
    set(HICLAW_USE_WEBSOCKETPP ON)
    message(STATUS "HiClaw gateway: using websocketpp (auto, LWS not found)")
  endif()
endif()
if(HICLAW_USE_LIBWEBSOCKETS AND NOT LibWebSockets_FOUND)
  set(HICLAW_USE_LIBWEBSOCKETS OFF)
  set(HICLAW_USE_WEBSOCKETPP ON)
  message(STATUS "HiClaw gateway: libwebsockets requested but not found, falling back to websocketpp")
endif()

# ---- websocketpp + Asio from third_party (clone into third_party/asio, third_party/websocketpp) ----
if(HICLAW_USE_WEBSOCKETPP)
  set(ASIO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/asio")
  set(WEBSOCKETPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/websocketpp")
  if(EXISTS "${ASIO_DIR}/asio/include/asio.hpp" AND EXISTS "${WEBSOCKETPP_DIR}/websocketpp/version.hpp")
    set(ASIO_INCLUDE_DIR "${ASIO_DIR}/asio/include")
    set(WEBSOCKETPP_INCLUDE_DIR "${WEBSOCKETPP_DIR}")
    message(STATUS "HiClaw gateway: using asio and websocketpp from third_party")
  else()
    message(FATAL_ERROR "Clone Asio and websocketpp into third_party:\n  git clone --depth 1 --branch asio-1-28-0 https://github.com/chriskohlhoff/asio.git third_party/asio\n  git clone --depth 1 --branch 0.8.2 https://github.com/zaphoyd/websocketpp.git third_party/websocketpp")
  endif()
endif()

# CLI11 (third_party) for command-line parsing
set(CLI11_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/CLI11")
if(EXISTS "${CLI11_DIR}/CMakeLists.txt")
  set(CLI11_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(CLI11_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  add_subdirectory(${CLI11_DIR} ${CMAKE_BINARY_DIR}/_deps/CLI11_build)
  set(HICLAW_HAS_CLI11 ON)
else()
  message(FATAL_ERROR "third_party/CLI11/CMakeLists.txt not found. Clone with: git clone --depth 1 --branch v2.3.2 https://github.com/CLIUtils/CLI11.git third_party/CLI11")
endif()

# spdlog (third_party) for logging
set(SPDLOG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/spdlog")
if(EXISTS "${SPDLOG_DIR}/CMakeLists.txt")
  set(SPDLOG_BUILD_EXAMPLE OFF CACHE BOOL "" FORCE)
  set(SPDLOG_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(SPDLOG_BUILD_SHARED OFF CACHE BOOL "" FORCE)
  add_subdirectory(${SPDLOG_DIR} ${CMAKE_BINARY_DIR}/_deps/spdlog_build)
  set(HICLAW_HAS_SPDLOG ON)
else()
  message(FATAL_ERROR "third_party/spdlog/CMakeLists.txt not found. Clone with: git clone --depth 1 --branch v1.14.0 https://github.com/gabime/spdlog.git third_party/spdlog")
endif()

# nlohmann/json (third_party) — clone repo into third_party/nlohmann_json
set(NLOHMANN_JSON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/nlohmann_json")
if(EXISTS "${NLOHMANN_JSON_DIR}/CMakeLists.txt")
  set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
  add_subdirectory(${NLOHMANN_JSON_DIR} ${CMAKE_BINARY_DIR}/_deps/nlohmann_json_build)
  set(HICLAW_HAS_NLOHMANN_JSON ON)
else()
  message(FATAL_ERROR "third_party/nlohmann_json not found. Clone: git clone --depth 1 --branch v3.11.3 https://github.com/nlohmann/json.git third_party/nlohmann_json")
endif()

# libhv (third_party) — HTTP client/server library with mbedTLS support
set(LIBHV_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/libhv")
set(MBEDTLS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/mbedtls")

# Check if mbedTLS is available in third_party for static linking
set(HICLAW_HAS_MBEDTLS_BUNDLED OFF)
if(EXISTS "${MBEDTLS_DIR}/CMakeLists.txt")
  set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
  set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
  set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
  set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
  add_subdirectory(${MBEDTLS_DIR} ${CMAKE_BINARY_DIR}/_deps/mbedtls_build)
  set(HICLAW_HAS_MBEDTLS_BUNDLED ON)
  message(STATUS "HiClaw: using bundled mbedTLS from third_party")
endif()

if(EXISTS "${LIBHV_DIR}/CMakeLists.txt")
  set(BUILD_SHARED OFF CACHE BOOL "" FORCE)
  set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(BUILD_UNITTEST OFF CACHE BOOL "" FORCE)
  set(WITH_HTTP ON CACHE BOOL "" FORCE)
  set(WITH_HTTP_SERVER ON CACHE BOOL "" FORCE)
  set(WITH_HTTP_CLIENT ON CACHE BOOL "" FORCE)
  set(LIBHV_INSTALL OFF CACHE BOOL "" FORCE)
  # Only enable mbedTLS if we have the bundled version (for static linking)
  if(HICLAW_HAS_MBEDTLS_BUNDLED)
    set(WITH_MBEDTLS ON CACHE BOOL "" FORCE)
    set(WITH_OPENSSL OFF CACHE BOOL "" FORCE)
    message(STATUS "HiClaw: enabling HTTPS support via bundled mbedTLS")
  else()
    set(WITH_MBEDTLS OFF CACHE BOOL "" FORCE)
    set(WITH_OPENSSL OFF CACHE BOOL "" FORCE)
    message(STATUS "HiClaw: HTTPS disabled (mbedTLS not found in third_party, HTTP only)")
    message(STATUS "To enable HTTPS, clone mbedTLS: git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git third_party/mbedtls")
  endif()
  add_subdirectory(${LIBHV_DIR} ${CMAKE_BINARY_DIR}/_deps/libhv_build)
  set(HICLAW_HAS_LIBHV ON)
  message(STATUS "HiClaw: using libhv for HTTP support")
else()
  message(FATAL_ERROR "third_party/libhv not found. Clone with: git clone --depth 1 --branch v1.3.3 https://github.com/ithewei/libhv.git third_party/libhv")
endif()

# Optional: line editing for config (UTF-8, backspace, cross-platform). Uses vendored third_party/linenoise-ng.
set(HICLAW_USE_LINENOISE ON CACHE BOOL "Use linenoise-ng for interactive config (TTY)")
if(HICLAW_USE_LINENOISE)
  set(LINENOISE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/linenoise-ng")
  if(NOT EXISTS "${LINENOISE_DIR}/include/linenoise.h")
    message(FATAL_ERROR "linenoise-ng not found at ${LINENOISE_DIR}. Ensure third_party/linenoise-ng is populated.")
  endif()
  message(STATUS "HiClaw CLI: using linenoise-ng from third_party for interactive prompts")
endif()

# Source files
set(HICLAW_SOURCES
  src/main.cpp
  src/agent/agent.cpp
  src/cli/cli.cpp
  src/config/config.cpp
  src/cron/schedule.cpp
  src/cron/store.cpp
  src/memory/file_memory.cpp
  src/net/async_agent.cpp
  src/net/call_handler.cpp
  src/net/gateway.cpp
  src/net/health_monitor.cpp
  src/net/idle_manager.cpp
  src/net/intent_router.cpp
  src/net/notification_handler.cpp
  src/net/http_client.cpp
  src/net/serve.cpp
  src/net/tool_router.cpp
  src/observability/log.cpp
  src/providers/ollama.cpp
  src/providers/openai_compatible.cpp
  src/security/path_guard.cpp
  src/session/store.cpp
  src/skills/skill_manager.cpp
  src/tools/memo_tool.cpp
  src/tools/tool.cpp
)

add_executable(hiclaw ${HICLAW_SOURCES})

if(HICLAW_USE_LINENOISE)
  target_compile_definitions(hiclaw PRIVATE HICLAW_USE_LINENOISE=1)
  target_sources(hiclaw PRIVATE
    ${LINENOISE_DIR}/src/linenoise.cpp
    ${LINENOISE_DIR}/src/ConvertUTF.cpp
    ${LINENOISE_DIR}/src/wcwidth.cpp
  )
  target_include_directories(hiclaw PRIVATE ${LINENOISE_DIR}/include ${LINENOISE_DIR}/src)
endif()

target_include_directories(hiclaw PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${LIBHV_DIR}
  ${LIBHV_DIR}/include
  ${LIBHV_DIR}/include/hv
)
target_link_libraries(hiclaw PRIVATE nlohmann_json::nlohmann_json CLI11::CLI11 hv_static spdlog::spdlog)

# Link bundled mbedTLS statically for single-binary deployment
if(HICLAW_HAS_MBEDTLS_BUNDLED)
  target_link_libraries(hiclaw PRIVATE mbedcrypto mbedx509 mbedtls)
endif()

if(HICLAW_USE_WEBSOCKETPP)
  target_include_directories(hiclaw PRIVATE ${ASIO_INCLUDE_DIR} ${WEBSOCKETPP_INCLUDE_DIR})
  target_compile_definitions(hiclaw PRIVATE
    HICLAW_USE_WEBSOCKETPP=1
    ASIO_STANDALONE
    _WEBSOCKETPP_CPP11_INTERNAL_
  )
  if(WIN32)
    target_compile_definitions(hiclaw PRIVATE _WIN32_WINNT=0x0601)
  endif()
  find_package(Threads REQUIRED)
  target_link_libraries(hiclaw PRIVATE Threads::Threads)
endif()

if(HICLAW_USE_LIBWEBSOCKETS)
  target_include_directories(hiclaw PRIVATE ${LIBWEBSOCKETS_INCLUDE_DIRS})
  target_link_libraries(hiclaw PRIVATE ${LIBWEBSOCKETS_LIBRARIES})
  target_compile_definitions(hiclaw PRIVATE HICLAW_USE_LIBWEBSOCKETS=1)
endif()

if(NOT HICLAW_USE_WEBSOCKETPP AND NOT HICLAW_USE_LIBWEBSOCKETS)
  message(STATUS "HiClaw gateway: no backend available (stub only)")
endif()

# MSVC: treat source and output as UTF-8
if(MSVC)
  target_compile_options(hiclaw PRIVATE /utf-8)
endif()

# Optional: OHOS toolchain
if(CMAKE_SYSTEM_NAME STREQUAL "OHOS")
  message(STATUS "Building for HarmonyOS: ${CMAKE_SYSTEM_PROCESSOR}")
  target_compile_options(hiclaw PRIVATE -D__MUSL__)
endif()

# Optional: Android toolchain
if(ANDROID)
  message(STATUS "Building for Android: ${ANDROID_ABI}, API ${ANDROID_PLATFORM}")
  # Android-specific definitions
  target_compile_definitions(hiclaw PRIVATE
    __ANDROID__
    ASIO_DISABLE_EPOLL
  )
  # Suppress some warnings on Android
  target_compile_options(hiclaw PRIVATE
    -Wno-unused-command-line-argument
  )
endif()
