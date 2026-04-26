#!/usr/bin/env bash
# Build hiclaw + Flutter desktop, bundle, and launch.
#
# Usage:
#   scripts/build-and-run.sh                    Build server & desktop, then run
#   scripts/build-and-run.sh --skip-server      Skip server build
#   scripts/build-and-run.sh --skip-desktop     Skip desktop build
#   scripts/build-and-run.sh --clean            Clean build before building

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PROJECT_ROOT/server"
DESKTOP_DIR="$PROJECT_ROOT/desktop"

SKIP_SERVER=false
SKIP_DESKTOP=false
CLEAN=false

for arg in "$@"; do
  case "$arg" in
    --skip-server)  SKIP_SERVER=true ;;
    --skip-desktop) SKIP_DESKTOP=true ;;
    --clean)        CLEAN=true ;;
  esac
done

# ========== Step 0: Kill running hiclaw ==========
echo "Killing any running hiclaw processes..."
pkill -f "hiclaw" 2>/dev/null || true
sleep 1
echo "Done."

# Detect platform and set server build script
OS="$(uname -s)"
case "$OS" in
  Darwin)
    SERVER_BUILD_SCRIPT="$SERVER_DIR/scripts/build-macos-arm64.sh"
    FLUTTER_BUILD_CMD="flutter build macos"
    RELEASE_DIR="$DESKTOP_DIR/build/macos/Build/Products/Release/bonio_desktop.app"
    ;;
  Linux)
    SERVER_BUILD_SCRIPT="$SERVER_DIR/scripts/build-linux-amd64.sh"
    FLUTTER_BUILD_CMD="flutter build linux"
    RELEASE_DIR="$DESKTOP_DIR/build/linux/x64/release/bundle"
    ;;
  *)
    echo "Error: Unsupported platform '$OS'"
    exit 1
    ;;
esac

# ========== Step 1: Build hiclaw ==========
if [[ "$SKIP_SERVER" == "true" ]]; then
  echo "[SKIP] Server build skipped."
else
  echo "============================================"
  echo "[1/3] Building hiclaw server..."
  echo "============================================"
  CLEAN_FLAG=""
  if [[ "$CLEAN" == "true" ]]; then
    CLEAN_FLAG="--clean"
    echo "Clean build requested."
  fi
  "$SERVER_BUILD_SCRIPT" $CLEAN_FLAG
fi

# ========== Step 2: Build Flutter desktop ==========
if [[ "$SKIP_DESKTOP" == "true" ]]; then
  echo "[SKIP] Desktop build skipped."
else
  echo ""
  echo "============================================"
  echo "[2/3] Building Flutter desktop..."
  echo "============================================"
  cd "$DESKTOP_DIR"
  if [[ "$CLEAN" == "true" ]]; then
    rm -rf build/macos build/linux 2>/dev/null || true
    echo "Cleaned desktop build directory."
  fi
  eval "$FLUTTER_BUILD_CMD"
fi

# ========== Step 3: Bundle hiclaw ==========
echo ""
echo "============================================"
echo "[3/3] Bundling hiclaw into desktop..."
echo "============================================"

if [[ "$OS" == "Darwin" ]]; then
  "$DESKTOP_DIR/scripts/bundle-hiclaw.sh" "$RELEASE_DIR"
else
  # Linux: copy hiclaw to build output directory
  mkdir -p "$RELEASE_DIR"
  cp "$SERVER_DIR/bin/hiclaw" "$RELEASE_DIR/hiclaw"
  chmod +x "$RELEASE_DIR/hiclaw"
  echo "Bundled hiclaw -> $RELEASE_DIR/hiclaw"
fi

# ========== Step 4: Launch ==========
echo ""
echo "============================================"
echo "Launching bonio_desktop..."
echo "============================================"

if [[ "$OS" == "Darwin" ]]; then
  open "$RELEASE_DIR"
else
  "$RELEASE_DIR/bonio_desktop" &
fi

echo "Done."
