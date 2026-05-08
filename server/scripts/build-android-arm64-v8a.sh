#!/usr/bin/env bash
# Build hiclaw for Android (aarch64-linux-android)
# Requires ANDROID_NDK_HOME to be set (path to Android NDK).
#
# Usage:
#   export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.1.10909125
#   scripts/build-android.sh
#
# Optional environment variables:
#   ANDROID_ABI       - Target ABI (default: arm64-v8a)
#   ANDROID_API_LEVEL - Minimum SDK version (default: 24)
#   HICLAW_BUILD_TYPE - Release or Debug (default: Release)
#
# Output: build/android/{ABI}/hiclaw

set -e

# Default settings
: "${ANDROID_ABI:=arm64-v8a}"
: "${ANDROID_API_LEVEL:=24}"
: "${HICLAW_BUILD_TYPE:=Release}"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "Error: ANDROID_NDK_HOME is not set."
  echo "Please set ANDROID_NDK_HOME to the path of Android NDK, e.g.:"
  echo "  export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.1.10909125"
  echo ""
  echo "Common locations:"
  echo "  Linux:   ~/Android/Sdk/ndk/<version>"
  echo "  macOS:   ~/Library/Android/sdk/ndk/<version>"
  echo "  Windows: %%LOCALAPPDATA%%\\Android\\Sdk\\ndk\\<version>"
  exit 1
fi

TOOLCHAIN="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/android-${ANDROID_ABI}"

if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "Error: Android NDK not found at $ANDROID_NDK_HOME"
  echo "Please verify the path and install NDK if needed."
  exit 1
fi
if [[ ! -f "$TOOLCHAIN" ]]; then
  echo "Error: Toolchain file not found: $TOOLCHAIN"
  echo "The NDK installation appears incomplete."
  exit 1
fi

# Find CMake
CMAKE_EXE="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/*/bin/cmake"
CMAKE_EXE=$(echo $CMAKE_EXE)
if [[ ! -x "$CMAKE_EXE" ]]; then
  if command -v cmake &> /dev/null; then
    CMAKE_EXE="cmake"
  else
    echo "Error: CMake not found. Please install CMake or use NDK's bundled CMake."
    exit 1
  fi
fi

# Find Ninja
NINJA_EXE="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/*/bin/ninja"
NINJA_EXE=$(echo $NINJA_EXE)
if [[ ! -x "$NINJA_EXE" ]]; then
  if command -v ninja &> /dev/null; then
    NINJA_EXE="ninja"
  else
    echo "Error: Ninja not found. Please install Ninja or use NDK's bundled Ninja."
    exit 1
  fi
fi

echo "============================================"
echo "Building HiClaw for Android"
echo "============================================"
echo "ANDROID_NDK_HOME:  $ANDROID_NDK_HOME"
echo "ANDROID_ABI:       $ANDROID_ABI"
echo "ANDROID_API_LEVEL: $ANDROID_API_LEVEL"
echo "BUILD_TYPE:        $HICLAW_BUILD_TYPE"
echo "Build dir:         $BUILD_DIR"
echo "CMake:             $CMAKE_EXE"
echo "Ninja:             $NINJA_EXE"
echo "============================================"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

"$CMAKE_EXE" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA_EXE" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
  -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE="$HICLAW_BUILD_TYPE" \
  -DHICLAW_GATEWAY_BACKEND=websocketpp \
  "$PROJECT_ROOT"

"$NINJA_EXE"

echo ""
echo "============================================"
echo "Build OK!"
echo "Binary: $BUILD_DIR/hiclaw"
echo "============================================"

# Copy to bin/
BIN_DIR="${PROJECT_ROOT}/bin"
mkdir -p "$BIN_DIR"
cp "$BUILD_DIR/hiclaw" "$BIN_DIR/hiclaw"
echo "Copied to $BIN_DIR/hiclaw"
