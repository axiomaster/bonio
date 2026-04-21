#!/usr/bin/env bash
# Bundle hiclaw binary into the macOS app bundle.
# Usage: scripts/bundle-hiclaw.sh <path_to_app_bundle>
#
# Prerequisite: server must be built for macOS (server/build/mac/hiclaw).
set -e

BUNDLE="${1:?Usage: bundle-hiclaw.sh <app_bundle_path>}"
RESOURCES="$BUNDLE/Contents/Resources"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HICLAW_BIN="$PROJECT_ROOT/server/build/mac/hiclaw"

if [[ ! -f "$HICLAW_BIN" ]]; then
  echo "Error: hiclaw binary not found at $HICLAW_BIN"
  echo "Build the server first: cd server && scripts/build-macos.sh"
  exit 1
fi

mkdir -p "$RESOURCES"
cp "$HICLAW_BIN" "$RESOURCES/hiclaw"
chmod +x "$RESOURCES/hiclaw"
echo "Bundled hiclaw -> $RESOURCES/hiclaw"
