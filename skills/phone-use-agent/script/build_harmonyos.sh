#!/bin/bash
# Build script for HarmonyOS
# Usage: ./build_harmonyos.sh [Release|Debug]

set -e

BUILD_TYPE=${1:-Release}
BUILD_DIR="build/harmonyos"

# Detect if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    OHOS_NDK="/mnt/d/tools/commandline-tools-windows/sdk/default/openharmony/native"
else
    OHOS_NDK="D:/tools/commandline-tools-windows/sdk/default/openharmony/native"
fi

NINJA_PATH="${OHOS_NDK}/build-tools/cmake/bin/ninja.exe"
TOOLCHAIN_FILE="$(pwd)/cmake/HarmonyOS-toolchain.cmake"

echo -e "\033[32mBuilding phone-use-agent for HarmonyOS...\033[0m"
echo -e "\033[36mUsing NDK: $OHOS_NDK\033[0m"

# Create build directory
mkdir -p "$BUILD_DIR"

# Configure
echo -e "\033[33mConfiguring...\033[0m"
cmake -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_MAKE_PROGRAM="$NINJA_PATH" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DBUILD_HARMONYOS=ON \
    -DBUILD_ANDROID=OFF

# Build
echo -e "\033[33mBuilding...\033[0m"
"$NINJA_PATH" -C "$BUILD_DIR"

echo -e "\033[32mBuild successful!\033[0m"
echo -e "\033[36mOutput: $BUILD_DIR/bin/phone-use-agent\033[0m"
