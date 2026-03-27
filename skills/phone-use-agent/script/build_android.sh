#!/bin/bash
# Build script for Android
# Usage: ./build_android.sh [Release|Debug]

set -e

BUILD_TYPE=${1:-Release}
BUILD_DIR="build/android"

echo -e "\033[32mBuilding phone-use-agent for Android...\033[0m"

# Find Android NDK
ANDROID_NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}"
if [ -z "$ANDROID_NDK" ]; then
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
        ANDROID_NDK=$(ls -d $HOME/Android/Sdk/ndk/*/ 2>/dev/null | sort -V | tail -1 | sed 's|/$||')
    fi
fi

if [ -z "$ANDROID_NDK" ]; then
    echo -e "\033[31mError: Android NDK not found!\033[0m"
    echo -e "\033[33mPlease set ANDROID_NDK_HOME or ANDROID_NDK environment variable\033[0m"
    exit 1
fi

echo -e "\033[36mUsing Android NDK: $ANDROID_NDK\033[0m"

# Create build directory
mkdir -p "$BUILD_DIR"

# Android NDK CMake toolchain
NDK_TOOLCHAIN="$ANDROID_NDK/build/cmake/android.toolchain.cmake"

# Configure
echo -e "\033[33mConfiguring...\033[0m"
cmake -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_TOOLCHAIN" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
    -DANDROID_STL=c++_static \
    -DBUILD_HARMONYOS=OFF \
    -DBUILD_ANDROID=ON

# Build
echo -e "\033[33mBuilding...\033[0m"
cmake --build "$BUILD_DIR" --config "$BUILD_TYPE"

echo -e "\033[32mBuild successful!\033[0m"
echo -e "\033[36mOutput: $BUILD_DIR/bin/phone-use-agent\033[0m"
