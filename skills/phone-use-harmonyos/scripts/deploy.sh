#!/bin/bash
# Deploy the freshly built phone-use-harmonyos binary to the connected device.
# Usage: ./scripts/deploy.sh [path-to-binary]
set -euo pipefail

export HDC_SERVER_PORT="${HDC_SERVER_PORT:-8710}"
HDC="${HDC:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc}"
BIN="${1:-/Users/ohci/code/phone-use-harmonyos/build/bin/phone-use-harmonyos}"
REMOTE=/data/local/bin/phone-use-harmonyos

if [ ! -f "$BIN" ]; then
  echo "error: binary not found: $BIN" >&2
  echo "build it first: cd /Users/ohci/code/phone-use-harmonyos && export OHOS_NDK=... && cmake -B build -G Ninja && ninja -C build" >&2
  exit 1
fi

"$HDC" file send "$BIN" "$REMOTE"
"$HDC" shell "chmod +x $REMOTE"
"$HDC" shell "$REMOTE --version" || true
echo "deployed: $REMOTE"
