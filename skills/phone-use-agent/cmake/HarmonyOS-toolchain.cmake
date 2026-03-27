# HarmonyOS Toolchain for CMake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Detect WSL vs native Windows
if(EXISTS "/proc/version")
    file(READ "/proc/version" PROC_VERSION)
    string(FIND "${PROC_VERSION}" "microsoft" IS_WSL)
    if(NOT IS_WSL EQUAL -1)
        # WSL environment
        set(OHOS_NDK "/mnt/d/tools/commandline-tools-windows/sdk/default/openharmony/native")
    else()
        # Native Linux
        set(OHOS_NDK "D:/tools/commandline-tools-windows/sdk/default/openharmony/native")
    endif()
else()
    # Native Windows
    set(OHOS_NDK "D:/tools/commandline-tools-windows/sdk/default/openharmony/native")
endif()

# Specify the cross compiler
set(CMAKE_C_COMPILER "${OHOS_NDK}/llvm/bin/clang.exe")
set(CMAKE_CXX_COMPILER "${OHOS_NDK}/llvm/bin/clang++.exe")

# Specify the target
set(CMAKE_C_COMPILER_TARGET aarch64-linux-ohos)
set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-ohos)

# Specify sysroot
set(CMAKE_SYSROOT "${OHOS_NDK}/sysroot")

# Search for programs in the build host directories
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
# Search for libraries and headers in the target directories
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
