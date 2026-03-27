# HarmonyOS CMake configuration
set(TARGET_NAME phone-use-agent)

# OpenHarmony NDK path
set(OHOS_NDK "D:/tools/commandline-tools-windows/sdk/default/openharmony/native")

# Cross-compilation settings
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT "${OHOS_NDK}/sysroot")

set(CMAKE_C_COMPILER "${OHOS_NDK}/llvm/bin/clang.exe")
set(CMAKE_CXX_COMPILER "${OHOS_NDK}/llvm/bin/clang++.exe")
set(CMAKE_C_COMPILER_TARGET aarch64-linux-ohos)
set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-ohos)

set(CMAKE_FIND_ROOT_PATH "${OHOS_NDK}/sysroot")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# HarmonyOS-specific compile flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -D__MUSL__ -D__OHOS__")

# Platform sources (use absolute paths for subdirectory access)
set(PLATFORM_SOURCES
    ${CMAKE_SOURCE_DIR}/src/platform/harmonyos/HarmonyOSPlatform.cpp
)

# Platform include directories
set(PLATFORM_INCLUDE_DIRS
    ${OHOS_NDK}/sysroot/usr/include
    ${OHOS_NDK}/sysroot/usr/include/network/netstack
    ${OHOS_NDK}/sysroot/usr/include/network/netmanager
)

# Platform libraries
set(PLATFORM_LIBRARIES
    c++
    m
    z
    ace_ndk.z.so
    hilog_ndk.z.so
)

# Platform definitions
set(PLATFORM_DEFINITIONS
    __OHOS__
    __MUSL__
)

# Library directories
link_directories(
    ${OHOS_NDK}/sysroot/usr/lib/aarch64-linux-ohos
    ${OHOS_NDK}/llvm/lib/aarch64-linux-ohos
)
