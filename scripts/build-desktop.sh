#!/usr/bin/env bash
# Build Flutter desktop, bundle hiclaw, and optionally launch.
# Requires hiclaw binary in server/bin/ (run build-server.sh first).
#
# Usage: scripts/build-desktop.sh [--clean] [--run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESKTOP_DIR="$PROJECT_ROOT/desktop"
SERVER_DIR="$PROJECT_ROOT/server"

CLEAN=false
RUN=false
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    --run)   RUN=true ;;
  esac
done

OS="$(uname -s)"

# Build Flutter
cd "$DESKTOP_DIR"
if [[ "$CLEAN" == "true" ]]; then
  rm -rf build/macos build/linux 2>/dev/null || true
  echo "Cleaned desktop build directory."
fi

echo "Building Flutter desktop..."
case "$OS" in
  Darwin) flutter build macos ;;
  Linux)  flutter build linux ;;
  *)      echo "Error: Unsupported platform '$OS'"; exit 1 ;;
esac

# Bundle hiclaw
echo "Bundling hiclaw..."
if [[ "$OS" == "Darwin" ]]; then
  APP="$DESKTOP_DIR/build/macos/Build/Products/Release/boji_desktop.app"
  "$DESKTOP_DIR/scripts/bundle-hiclaw.sh" "$APP"
else
  BUNDLE="$DESKTOP_DIR/build/linux/x64/release/bundle"
  mkdir -p "$BUNDLE"
  cp "$SERVER_DIR/bin/hiclaw" "$BUNDLE/hiclaw"
  chmod +x "$BUNDLE/hiclaw"
  echo "Bundled hiclaw -> $BUNDLE/hiclaw"
fi

# Optionally launch
if [[ "$RUN" == "true" ]]; then
  echo "Launching boji_desktop..."
  if [[ "$OS" == "Darwin" ]]; then
    open "$APP"
  else
    "$DESKTOP_DIR/build/linux/x64/release/bundle/boji_desktop" &
  fi
fi
