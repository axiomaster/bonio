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

log "Applying HarmonyOS attachment compatibility"
"$HDC" shell "
  ATTACHMENT_FILE=$DSH_NM/@deepseek-ai/dsh-attachment-local/lib/index.js
  if [ -f \"\${ATTACHMENT_FILE}\" ] && ! grep -q 'error.code === \"EINVAL\"' \"\${ATTACHMENT_FILE}\"; then
    sed -i \"/async function syncDirectory(path)/,/^}/ s/[[:space:]]*await handle.sync();/\\ttry { await handle.sync(); } catch (error) { if (!(error instanceof Error \\&\\& \\\"code\\\" in error \\&\\& error.code === \\\"EINVAL\\\")) throw error; }/\" \"\${ATTACHMENT_FILE}\"
  fi
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
- id: agent-default-model
  config:
    provider: deepseek-official
    model: deepseek-v4-flash-vision-exp

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

log "Ensuring bash shim (dsh spawns literal 'bash'; OHOS only ships /bin/sh)"
"$HDC" shell "ln -sf /bin/sh /usr/local/bin/bash 2>/dev/null || echo 'WARN: cannot write /usr/local/bin (run: hdc target mount)'"

log "Restarting daemon (self-healing loop)"
# Kill EVERY supervisor + dsh instance. Relying on pkill alone let duplicate
# dsh-daemon.sh supervisors pile up (dozens racing to spawn dsh, losers crash
# with EADDRINUSE every 15s), so also kill via ps|grep as a pkill-free path.
"$HDC" shell '
  ps -ef | grep -E "dsh-daemon.sh|dsh --profile bonio|bin[.]js --profile bonio" | grep -v grep | while read -r _u _p _r; do
    kill -9 "$_p" 2>/dev/null
  done
  pkill -9 -f dsh-daemon.sh 2>/dev/null
  pkill -9 -f "bin.js --profile bonio" 2>/dev/null
  sleep 1
  rm -f /data/local/dsh-daemon.pid
  true
'
"$HDC" shell "
  HOME=$DEVICE_HOME LD_LIBRARY_PATH=/usr/local/lib nohup /data/local/bin/dsh-daemon.sh > /dev/null 2>&1 &
"

sleep 25
log "Verifying gateway"
"$HDC" shell "netstat -tlnp 2>/dev/null | grep -E '10724|$WEB_PORT' | head -3"

log "Done. From the host:"
log "  $HDC fport tcp:10724 tcp:10724"
log "  cd $BRIDGE_DIR/test && BRIDGE_TOKEN=$TOKEN node smoke-client.mjs chat"
