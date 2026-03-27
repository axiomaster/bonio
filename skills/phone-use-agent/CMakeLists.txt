cmake_minimum_required(VERSION 3.16)

# Project settings
project(phone-use-agent VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build options
option(BUILD_HARMONYOS "Build for HarmonyOS platform" OFF)
option(BUILD_ANDROID "Build for Android platform" OFF)
option(BUILD_TESTS "Build test executables" ON)

# Common sources (use absolute paths for subdirectory access)
set(CORE_SOURCES
    ${CMAKE_SOURCE_DIR}/src/core/TaskExecutor.cpp
    ${CMAKE_SOURCE_DIR}/src/AutoGLMClient.cpp
    ${CMAKE_SOURCE_DIR}/src/ConfigManager.cpp
    ${CMAKE_SOURCE_DIR}/src/CliArgs.cpp
    ${CMAKE_SOURCE_DIR}/src/HttpClient.cpp
    ${CMAKE_SOURCE_DIR}/src/platform/PlatformFactory.cpp
)

set(COMMON_HEADERS
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/core
    ${CMAKE_SOURCE_DIR}/include/nlohmann
    ${CMAKE_SOURCE_DIR}/src
)

# Platform-specific configuration
if(BUILD_HARMONYOS)
    message(STATUS "Building for HarmonyOS platform")
    include(cmake/HarmonyOS.cmake)
elseif(BUILD_ANDROID)
    message(STATUS "Building for Android platform")
    include(cmake/Android.cmake)
else()
    # Auto-detect platform or default to host build
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
        # Likely Android or HarmonyOS cross-compile
        message(STATUS "Cross-compiling for aarch64-linux, defaulting to Android")
        include(cmake/Android.cmake)
    else()
        message(STATUS "Building for host platform (development mode)")
        include(cmake/Host.cmake)
    endif()
endif()

# Main executable
add_executable(${TARGET_NAME}
    src/main.cpp
    ${CORE_SOURCES}
    ${PLATFORM_SOURCES}
)

target_include_directories(${TARGET_NAME} PRIVATE
    ${COMMON_HEADERS}
    ${PLATFORM_INCLUDE_DIRS}
)

target_link_libraries(${TARGET_NAME} PRIVATE
    ${PLATFORM_LIBRARIES}
)

target_compile_definitions(${TARGET_NAME} PRIVATE
    ${PLATFORM_DEFINITIONS}
)

set_target_properties(${TARGET_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Tests
if(BUILD_TESTS)
    add_subdirectory(test)
endif()
