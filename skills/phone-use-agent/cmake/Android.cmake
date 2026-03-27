# Android CMake configuration
set(TARGET_NAME phone-use-agent)

# Android NDK path - adjust as needed
if(NOT DEFINED ANDROID_NDK)
    if(DEFINED ENV{ANDROID_NDK_HOME})
        set(ANDROID_NDK $ENV{ANDROID_NDK_HOME})
    elseif(DEFINED ENV{ANDROID_NDK})
        set(ANDROID_NDK $ENV{ANDROID_NDK})
    elseif(EXISTS "C:/Users/$ENV{USERNAME}/AppData/Local/Android/Sdk/ndk")
        file(GLOB ANDROID_NDK_CANDIDATES "C:/Users/$ENV{USERNAME}/AppData/Local/Android/Sdk/ndk/*")
        list(SORT ANDROID_NDK_CANDIDATES ORDER DESCENDING)
        list(GET ANDROID_NDK_CANDIDATES 0 ANDROID_NDK)
    elseif(EXISTS "$ENV{HOME}/Android/Sdk/ndk")
        file(GLOB ANDROID_NDK_CANDIDATES "$ENV{HOME}/Android/Sdk/ndk/*")
        list(SORT ANDROID_NDK_CANDIDATES ORDER DESCENDING)
        list(GET ANDROID_NDK_CANDIDATES 0 ANDROID_NDK)
    else()
        message(FATAL_ERROR "ANDROID_NDK not found. Please set ANDROID_NDK or ANDROID_NDK_HOME environment variable")
    endif()
endif()

message(STATUS "Using Android NDK: ${ANDROID_NDK}")

# Android-specific settings
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 24)  # Android 7.0+
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
set(CMAKE_ANDROID_NDK ${ANDROID_NDK})
set(CMAKE_ANDROID_STL_TYPE c++_static)

# Android-specific compile flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -D__ANDROID__")

# Platform sources (use absolute paths for subdirectory access)
set(PLATFORM_SOURCES
    ${CMAKE_SOURCE_DIR}/src/platform/android/AndroidPlatform.cpp
)

# Platform include directories
set(PLATFORM_INCLUDE_DIRS
    ${ANDROID_NDK}/toolchains/llvm/prebuilt/${CMAKE_HOST_SYSTEM_NAME}-x86_64/sysroot/usr/include
    ${ANDROID_NDK}/toolchains/llvm/prebuilt/${CMAKE_HOST_SYSTEM_NAME}-x86_64/sysroot/usr/include/aarch64-linux-android
)

# Platform libraries - Android uses standard libc
set(PLATFORM_LIBRARIES
    c++
    log
)

# Platform definitions
set(PLATFORM_DEFINITIONS
    __ANDROID__
)
