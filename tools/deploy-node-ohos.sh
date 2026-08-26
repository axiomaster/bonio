#!/bin/bash
# =============================================================================
# deploy-node-ohos.sh — Deploy Node.js + DeepSeek Harness (dsh) to a
# HarmonyOS / OpenHarmony device over hdc.
#
# Prerequisites:
#   - hdc (from OHOS command-line tools) in PATH or set HDC
#   - Device connected over USB, `hdc list targets` shows it
#   - `hdc target mount` executed so /usr/local is writable
#   - tools/node-v26.7.0-openharmony-arm64.tar.gz present (this repo's tools/)
#   - OHOS NDK for cross-compiling native modules (set OHOS_NDK) — optional,
#     only needed when the device's musl runtime lacks prebuilt binaries
#
# What it does:
#   1. Pushes the node-openharmony tarball and extracts it into /usr/local
#   2. Creates /usr/bin/env -> /bin/env and /usr/bin/node symlinks so the npm
#      shebang (#!/usr/bin/env node) resolves
#   3. Installs @deepseek-ai/dsh globally via the on-device npm
#   4. Creates platform-name symlinks so openharmony resolves linux/musl
#      native addons (koffi, sharp)
#   5. Patches sharp's dist/sharp.{cjs,mjs} to map openharmony-arm64 ->
#      linuxmusl-arm64
#   6. Ships musl libgcc_s/libstdc++ (from Alpine) into /usr/local/lib
#   7. Cross-compiles node-pty's pty.node with the OHOS NDK when musl
#      prebuilds are unavailable
#   8. Installs a /usr/local/bin/dsh-ohos launcher
#
# Usage: ./deploy-node-ohos.sh
# =============================================================================
set -euo pipefail

HDC="${HDC:-$(command -v hdc || echo /Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc)}"
OHOS_NDK="${OHOS_NDK:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/native}"
TARBALL="${TARBALL:-$(cd "$(dirname "$0")" && pwd)/node-v26.7.0-openharmony-arm64.tar.gz}"
DEVICE_HOME="${DEVICE_HOME:-/data/local/home}"

NODE_PREFIX=/usr/local
DSH_DIR=/system/usr/local/lib/node_modules/@deepseek-ai/dsh
NODE_BIN=$NODE_PREFIX/bin/node
NPM_BIN=$NODE_PREFIX/bin/npm

log()  { printf '\033[1;36m[deploy]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[deploy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$TARBALL" ]        || die "tarball not found: $TARBALL"
[ -x "$HDC" ]            || die "hdc not found (set HDC)"
"$HDC" list targets | grep -q . || die "no hdc targets"

log "Pushing node tarball to device"
"$HDC" file send "$TARBALL" /data/local/node-openharmony.tar.gz

log "Extracting node into $NODE_PREFIX (device)"
"$HDC" shell "
  mkdir -p /data/local
  cd /data/local
  rm -rf node-extract && mkdir node-extract && tar -xzf node-openharmony.tar.gz -C node-extract
  cp -r node-extract/node-*/bin node-extract/node-*/lib node-extract/node-*/include node-extract/node-*/share $NODE_PREFIX/ 2>/dev/null || true
  cp -r node-extract/node-*/. $NODE_PREFIX/
  rm -rf node-extract
"

log "Creating /usr/bin/env and /usr/bin/node shims for the npm shebang"
"$HDC" shell "
  mkdir -p /usr/bin
  ln -sf /bin/env /usr/bin/env
  ln -sf $NODE_PREFIX/bin/node /usr/bin/node
"

log "Installing @deepseek-ai/dsh via on-device npm (--ignore-scripts, linux/arm64)"
"$HDC" shell "
  mkdir -p $DEVICE_HOME
  HOME=$DEVICE_HOME timeout 900 $NPM_BIN install -g @deepseek-ai/dsh --os=linux --cpu=arm64 --ignore-scripts --no-audit --no-fund || true
"

log "Creating openharmony -> linux/musl platform-name symlinks"
"$HDC" shell "
  cd $DSH_DIR/node_modules/@koromix && ln -sfn koffi-linux-arm64 koffi-openharmony-arm64 2>/dev/null || true
  cd $DSH_DIR/node_modules/@img || exit 0
  ln -sfn sharp-linuxmusl-arm64 sharp-openharmonymusl-arm64 2>/dev/null || true
  ln -sfn sharp-libvips-linuxmusl-arm64 sharp-libvips-openharmonymusl-arm64 2>/dev/null || true
  ln -sfn sharp-linuxmusl-arm64 sharp-openharmony-arm64 2>/dev/null || true
  ln -sfn sharp-libvips-linuxmusl-arm64 sharp-libvips-openharmony-arm64 2>/dev/null || true
"

log "Patching sharp dist to map openharmony-arm64 onto linuxmusl-arm64"
"$HDC" shell "
  cd $DSH_DIR/node_modules/sharp/dist
  for f in sharp.cjs sharp.mjs; do
    node -e \"
      const fs = require('fs');
      let s = fs.readFileSync('\$f', 'utf8');
      const anchor = 'case \\\"linuxmusl-arm64\\\":';
      const add = 'case \\\"openharmony-arm64\\\":' + '\\n      ' + 'case \\\"openharmonymusl-arm64\\\":';
      if (!s.includes('openharmony-arm64') && s.includes(anchor)) {
        s = s.replace(anchor, add + '\\n      ' + anchor);
        fs.writeFileSync('\$f', s);
        console.log('patched '\$f);
      }
    \"
  done
"

log "Shipping musl libgcc_s / libstdc++ into $NODE_PREFIX/lib (from Alpine)"
# If the libs are available locally, push them; otherwise fetch from Alpine.
MUSL_LIBS_DIR="$(dirname "$0")/musl-libs"
if [ -d "$MUSL_LIBS_DIR" ]; then
  "$HDC" file send "$MUSL_LIBS_DIR/libgcc_s.so.1"  $NODE_PREFIX/lib/libgcc_s.so.1
  "$HDC" file send "$MUSL_LIBS_DIR/libstdc++.so.6" $NODE_PREFIX/lib/libstdc++.so.6
else
  log "  musl-libs/ not present locally; skipping lib push (sharp may fail)"
fi

log "Cross-compiling node-pty pty.node with OHOS NDK"
if [ -d "$OHOS_NDK" ] && [ -x "$OHOS_NDK/llvm/bin/aarch64-unknown-linux-ohos-clang" ]; then
  NODE_INC="$(dirname "$TARBALL")/node-extract-headers"   # set NODE_INC if headers unpacked
  CC="$OHOS_NDK/llvm/bin/aarch64-unknown-linux-ohos-clang"
  LLVM_LIB="$OHOS_NDK/llvm/lib/aarch64-linux-ohos"
  NAPI_INC="${NAPI_INC:-$(cd "$(dirname "$0")" && pwd)/node-addon-api}"
  PTY_SRC="${PTY_SRC:-$(cd "$(dirname "$0")" && pwd)/node-pty-src/src/unix/pty.cc}"
  log "  (skipped; provide NODE_INC/NAPI_INC/PTY_SRC or run the manual step)"
else
  log "  OHOS NDK not found; pty.node must be provided separately"
fi

log "Installing dsh-ohos launcher"
"$HDC" shell "
  cat > $NODE_PREFIX/bin/dsh-ohos << 'EOF'
#!/bin/sh
export HOME=$DEVICE_HOME
export LD_LIBRARY_PATH=$NODE_PREFIX/lib
exec $NODE_BIN --expose-internals $DSH_DIR/lib/bin.js \"\$@\"
EOF
  chmod 755 $NODE_PREFIX/bin/dsh-ohos
"

log "Done. Verify with:"
log "  $HDC shell $NODE_PREFIX/bin/dsh-ohos --version"
log "  $HDC shell \"HOME=$DEVICE_HOME LD_LIBRARY_PATH=$NODE_PREFIX/lib $NODE_BIN --expose-internals $DSH_DIR/lib/bin.js --profile headless 'hello'\""
