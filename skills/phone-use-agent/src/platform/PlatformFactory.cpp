#include "platform/Platform.h"
#include <iostream>

// Platform detection macros
// __OHOS__ and __ANDROID__ are defined via CMake PLATFORM_DEFINITIONS
#if defined(__OHOS__)
    #include "platform/harmonyos/HarmonyOSPlatform.h"
    #define PLATFORM_HARMONYOS 1
#elif defined(__ANDROID__)
    #include "platform/android/AndroidPlatform.h"
    #define PLATFORM_ANDROID 1
#elif defined(_HOST_BUILD_)
    // For development/testing on host - include both for flexibility
    #include "platform/android/AndroidPlatform.h"
    #include "platform/harmonyos/HarmonyOSPlatform.h"
    #define PLATFORM_ANDROID 1
    #define PLATFORM_HARMONYOS 1
#else
    // Default fallback
    #if defined(_WIN32) || defined(__linux__)
        #include "platform/android/AndroidPlatform.h"
        #define PLATFORM_ANDROID 1
    #endif
#endif

namespace PlatformFactory {

std::unique_ptr<IPlatform> create() {
#if PLATFORM_HARMONYOS
    std::cout << "Detected platform: HarmonyOS" << std::endl;
    return createHarmonyOS();
#elif PLATFORM_ANDROID
    std::cout << "Detected platform: Android" << std::endl;
    return createAndroid();
#else
    std::cerr << "Unknown platform, defaulting to Android" << std::endl;
    return createAndroid();
#endif
}

std::unique_ptr<IPlatform> createHarmonyOS() {
#if PLATFORM_HARMONYOS
    return std::make_unique<HarmonyOSPlatform>();
#else
    std::cerr << "HarmonyOS platform not available on this build" << std::endl;
    return nullptr;
#endif
}

std::unique_ptr<IPlatform> createAndroid() {
#if PLATFORM_ANDROID
    return std::make_unique<AndroidPlatform>();
#else
    std::cerr << "Android platform not available on this build" << std::endl;
    return nullptr;
#endif
}

} // namespace PlatformFactory
