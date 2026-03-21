#!/usr/bin/env bash
# Deploy hiclaw to Android device via adb
#
# Usage:
#   scripts/deploy-android.sh [ABI]
#   scripts/deploy-android.sh arm64-v8a
#
# If ABI is not specified, uses arm64-v8a (most common for modern devices)

set -e

ABI="${1:-arm64-v8a}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/android/${ABI}"
BINARY="${BUILD_DIR}/hiclaw"
REMOTE_PATH="/data/local/tmp/hiclaw"

# Check if binary exists
if [[ ! -f "$BINARY" ]]; then
  echo "Error: Binary not found at $BINARY"
  echo "Please build first: scripts/build-android.sh"
  echo "Make sure ANDROID_ABI=$ABI was used."
  exit 1
fi

# Check if adb is available
if ! command -v adb &> /dev/null; then
  echo "Error: adb not found in PATH."
  echo "Please add Android SDK platform-tools to PATH."
  exit 1
fi

# Check if device is connected
if ! adb get-state &> /dev/null; then
  echo "Error: No Android device connected or unauthorized."
  echo "Please connect a device and authorize USB debugging."
  exit 1
fi

echo "============================================"
echo "Deploying HiClaw to Android device"
echo "============================================"
echo "ABI:         $ABI"
echo "Binary:      $BINARY"
echo "Remote path: $REMOTE_PATH"
echo "============================================"

echo "Pushing binary..."
adb push "$BINARY" "$REMOTE_PATH"

echo "Setting executable permission..."
adb shell chmod +x "$REMOTE_PATH"

echo ""
echo "Testing binary..."
adb shell "$REMOTE_PATH --version"

echo ""
echo "============================================"
echo "Deploy OK!"
echo ""
echo "To run gateway:"
echo "  adb shell"
echo "  $REMOTE_PATH gateway --port 18789"
echo "============================================"
