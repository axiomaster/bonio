#!/usr/bin/env bash
# Build hiclaw server only.
#
# Usage: scripts/build-server.sh [--clean]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../server" && pwd)"

CLEAN_FLAG=""
for arg in "$@"; do
  case "$arg" in --clean) CLEAN_FLAG="--clean" ;; esac
done

OS="$(uname -s)"
case "$OS" in
  Darwin) "$SERVER_DIR/scripts/build-macos-arm64.sh" $CLEAN_FLAG ;;
  Linux)  "$SERVER_DIR/scripts/build-linux-amd64.sh" $CLEAN_FLAG ;;
  *)      echo "Error: Unsupported platform '$OS'"; exit 1 ;;
esac
