#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NDK_CLANG="${OHOS_NDK_CLANG:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/native/llvm/bin/clang++}"
SYSROOT="${OHOS_SYSROOT:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/native/sysroot}"
OUTPUT="${SCRIPT_DIR}/bonio-proxy-ime"

if [ ! -x "$NDK_CLANG" ]; then
    echo "Error: Clang++ not found at $NDK_CLANG" >&2
    exit 1
fi

echo "Building bonio-proxy-ime (aarch64-linux-ohos)..."
"$NDK_CLANG" \
    --target=aarch64-linux-ohos \
    --sysroot="$SYSROOT" \
    -std=c++17 \
    -O2 \
    -fPIE -pie \
    -Wl,-z,relro,-z,now \
    -o "$OUTPUT" \
    "${SCRIPT_DIR}/bonio_proxy_ime.cpp"

echo "Built: $OUTPUT ($(ls -lh "$OUTPUT" | awk '{print $5}'))"
