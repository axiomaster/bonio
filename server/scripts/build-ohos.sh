#!/usr/bin/env bash
# Build hiclaw for HarmonyOS (aarch64-linux-ohos) on WSL/Linux.
# Requires OHOS_NDK_HOME to be set (path to OpenHarmony native SDK).
#
# Usage: scripts/build-ohos.sh
# Output: build/ohos/hiclaw

set -e

if [[ -z "${OHOS_NDK_HOME:-}" ]]; then
  echo "Error: OHOS_NDK_HOME is not set."
  echo "Please set OHOS_NDK_HOME to the path of OpenHarmony native SDK, e.g.:"
  echo "  export OHOS_NDK_HOME=/path/to/sdk/default/openharmony/native"
  exit 1
fi

TOOLCHAIN="${OHOS_NDK_HOME}/build/cmake/ohos.toolchain.cmake"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/ohos"

if [[ ! -d "$OHOS_NDK_HOME" ]]; then
  echo "Error: OHOS NDK not found at $OHOS_NDK_HOME"
  echo "Set OHOS_NDK_HOME or install command-line-tools to the path above."
  exit 1
fi
if [[ ! -f "$TOOLCHAIN" ]]; then
  echo "Error: Toolchain file not found: $TOOLCHAIN"
  exit 1
fi

echo "============================================"
echo "Building HiClaw for HarmonyOS"
echo "============================================"
echo "OHOS_NDK_HOME: $OHOS_NDK_HOME"
echo "Build dir:     $BUILD_DIR"
echo.

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" "$PROJECT_ROOT"
ninja

echo ""
echo "============================================"
echo "Build OK!"
echo "Binary: $BUILD_DIR/hiclaw"
echo "============================================"
