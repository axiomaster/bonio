#!/bin/bash
# =============================================================================
# deploy-bonio-bridge-ohos.sh — deploy the bonio-bridge dsh plugin to an OHOS
# device and start the dsh bonio profile under the daemon.
#
# Prereqs: hdc + connected device (hdc target mount for /usr/local writes).
# =============================================================================
set -euo pipefail

HDC="${HDC:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/../dsh-plugins/bonio-bridge"
DEVICE_HOME=/data/local/home
DSH_NM=/system/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules
TOKEN="${BONIO_BRIDGE_TOKEN:-bonio-local-token}"
WEB_PORT="${BONIO_WEB_PORT:-13082}"

log() { printf '\033[1;36m[deploy-bridge]\033[0m %s\n' "$*"; }

[ -x "$HDC" ] || { echo "hdc not found"; exit 1; }
"$HDC" list targets | grep -q . || { echo "no device"; exit 1; }

log "Packing bonio-bridge"
tar -czf /tmp/bonio-bridge.tgz -C "$BRIDGE_DIR" build package.json cordis.patch.yml

log "Pushing to device"
"$HDC" file send /tmp/bonio-bridge.tgz /data/local/bonio-bridge.tgz

log "Extracting into dsh node_modules"
"$HDC" shell "
  mkdir -p $DSH_NM/@bonio/dsh-bonio-bridge
  cd $DSH_NM/@bonio/dsh-bonio-bridge
  tar -xzf /data/local/bonio-bridge.tgz
  find build -name '._*' -delete
"

log "Creating bonio profile (locally, then pushing)"
PROFILE_DIR="$(mktemp -d)"
mkdir -p "$PROFILE_DIR/bonio/node_modules/@bonio"
cp -r "$BRIDGE_DIR" "$PROFILE_DIR/bonio/node_modules/@bonio/dsh-bonio-bridge"
rm -rf "$PROFILE_DIR/bonio/node_modules/@bonio/dsh-bonio-bridge/src" \
       "$PROFILE_DIR/bonio/node_modules/@bonio/dsh-bonio-bridge/test" \
       "$PROFILE_DIR/bonio/node_modules/@bonio/dsh-bonio-bridge/tsconfig.json"
cat > "$PROFILE_DIR/bonio/package.json" << PKGEOF
{
  "name": "dsh-profile-bonio",
  "private": true,
  "dependencies": {},
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "@bonio/dsh-bonio-bridge"
      ]
    }
  }
}
PKGEOF
printf '[]\n' > "$PROFILE_DIR/bonio/cordis.yml"
cat > "$PROFILE_DIR/bonio/cordis.patch.yml" << PATCHEOF
# bonio profile patch layer.
- id: bonio-bridge
  config:
    port: 10724
    token: $TOKEN
    tools: route
PATCHEOF
tar -czf /tmp/bonio-profile.tgz -C "$PROFILE_DIR" bonio
"$HDC" file send /tmp/bonio-profile.tgz /data/local/bonio-profile.tgz
"$HDC" shell "
  rm -rf $DEVICE_HOME/.dsh/profiles/bonio
  mkdir -p $DEVICE_HOME/.dsh/profiles
  cd $DEVICE_HOME/.dsh/profiles
  tar -xzf /data/local/bonio-profile.tgz
"
rm -rf "$PROFILE_DIR"

log "Installing daemon script"
"$HDC" file send "$SCRIPT_DIR/dsh-daemon.sh" /data/local/bin/dsh-daemon.sh
"$HDC" shell "chmod 755 /data/local/bin/dsh-daemon.sh"

log "Restarting daemon (self-healing loop)"
"$HDC" shell "pkill -f 'bin.js --profile bonio' 2>/dev/null; pkill -f 'dsh-daemon.sh' 2>/dev/null; sleep 1; rm -f /data/local/dsh-daemon.pid; true"
"$HDC" shell "
  HOME=$DEVICE_HOME LD_LIBRARY_PATH=/usr/local/lib nohup /data/local/bin/dsh-daemon.sh > /dev/null 2>&1 &
"

sleep 25
log "Verifying gateway"
"$HDC" shell "netstat -tlnp 2>/dev/null | grep -E '10724|$WEB_PORT' | head -3"

log "Done. From the host:"
log "  $HDC fport tcp:10724 tcp:10724"
log "  cd $BRIDGE_DIR/test && BRIDGE_TOKEN=$TOKEN node smoke-client.mjs chat"
