#!/bin/bash
# ============================================================================
# ohos-cli.sh — invoke a HarmonyOS/OpenHarmony system CLI tool on the device
#               connected via HDC (HarmonyOS Device Connector).
#
# The tools live on the device under /system/bin/cli_tool/executable/ and are
# documented by JSON schema files under /system/bin/cli_tool/configs/.
#
# Usage:
#   ./ohos-cli.sh list
#       List all available cli_tool executables on the connected device.
#   ./ohos-cli.sh <tool> --help
#       Show usage/help for a specific tool (e.g. ohos-wifiManager --help).
#   ./ohos-cli.sh <tool> <subcommand> [--flag value ...]
#       Run a subcommand, e.g.:
#         ./ohos-cli.sh ohos-queryTime get-wall-time
#         ./ohos-cli.sh ohos-pasteboard set-data --text "Hello World"
#         ./ohos-cli.sh ohos-audioManager set-volume --volume 10 --type STREAM_RING
#         ./ohos-cli.sh ohos-wifiManager scan-start
#
# Environment:
#   HDC   path to the hdc binary (default: the one bundled with the local
#         OpenHarmony command-line tools SDK).
#   HDC_TARGET  optional device serial/target, passed as hdc -t <target>.
#
# Output: JSON on stdout: {"type":"result","status":"success","data":{...}}
#         or {"type":"result","status":"failed","errCode":"...","errMsg":"..."}.
#         Some tools also emit [LOG]/[INFO]-prefixed lines to stdout.
# ============================================================================
set -euo pipefail

HDC="${HDC:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc}"
BASE="/system/bin/cli_tool/executable"

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") <tool> [subcommand] [args...]" >&2
  echo "       $(basename "$0") list" >&2
  exit 2
fi

# Compose the hdc command prefix (optionally targeting a specific device).
HDC_CMD=("$HDC")
if [ -n "${HDC_TARGET:-}" ]; then
  HDC_CMD+=(-t "$HDC_TARGET")
fi

case "$1" in
  list)
    "${HDC_CMD[@]}" shell ls "$BASE"
    ;;
  *)
    TOOL="$1"
    shift
    # Rebuild the remote command line with proper shell quoting so values
    # containing spaces/special characters survive transport to the device.
    REMOTE="$BASE/$TOOL"
    for a in "$@"; do
      REMOTE="$REMOTE $(printf '%q' "$a")"
    done
    exec "${HDC_CMD[@]}" shell "$REMOTE"
    ;;
esac
