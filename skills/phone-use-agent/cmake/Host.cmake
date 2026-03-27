# Host CMake configuration (for development/testing on host machine)
set(TARGET_NAME phone-use-agent)

# Host build uses Android platform implementation for testing
set(PLATFORM_SOURCES
    ${CMAKE_SOURCE_DIR}/src/platform/android/AndroidPlatform.cpp
)

# Platform include directories
set(PLATFORM_INCLUDE_DIRS
    include
)

# Platform libraries
set(PLATFORM_LIBRARIES
    pthread
    dl
)

# Platform definitions
set(PLATFORM_DEFINITIONS
    _HOST_BUILD_
)

message(STATUS "Building for host platform (development/testing mode)")
message(STATUS "Note: This build will not run on actual devices")
