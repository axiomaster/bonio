#!/bin/bash
# Run phone-use-harmonyos on the connected device via hdc.
# Usage: ./scripts/run.sh --task '...' [--max-step N] [--verbose] [--apikey KEY]
set -euo pipefail

HDC="${HDC:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc}"
REMOTE=/data/local/bin/phone-use-harmonyos

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") --task '描述' [--max-step N] [--verbose] [--apikey KEY]" >&2
  exit 2
fi

# Rebuild remote command with safe quoting (double shell layer: local bash → hdc → device sh)
REMOTE_CMD="$REMOTE"
for a in "$@"; do
  REMOTE_CMD="$REMOTE_CMD $(printf '%q' "$a")"
done
exec "$HDC" shell "$REMOTE_CMD"
