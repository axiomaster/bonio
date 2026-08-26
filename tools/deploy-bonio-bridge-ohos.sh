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

log "Creating bonio profile"
"$HDC" shell "
  mkdir -p $DEVICE_HOME/.dsh/profiles/bonio/node_modules/@bonio
  cp -r $DSH_NM/@bonio/dsh-bonio-bridge $DEVICE_HOME/.dsh/profiles/bonio/node_modules/@bonio/
  cat > $DEVICE_HOME/.dsh/profiles/bonio/package.json << PKGEOF
{
  \"name\": \"dsh-profile-bonio\",
  \"private\": true,
  \"dependencies\": {},
  \"dsh\": {
    \"profile\": {
      \"bundles\": [
        \"@deepseek-ai/dsh-base\",
        \"@deepseek-ai/dsh-web-app\",
        \"@bonio/dsh-bonio-bridge\"
      ]
    }
  }
}
PKGEOF
  printf '[]\n' > $DEVICE_HOME/.dsh/profiles/bonio/cordis.yml
  cat > $DEVICE_HOME/.dsh/profiles/bonio/cordis.patch.yml << PATCHEOF
# bonio profile patch layer.
- id: bonio-bridge
  config:
    port: 10724
    token: $TOKEN
    tools: route
PATCHEOF
"

log "Installing daemon script"
"$HDC" shell "
  mkdir -p /data/local/bin
  cat > /data/local/bin/dsh-daemon.sh << DAEMONEOF
#!/bin/sh
export HOME=$DEVICE_HOME
export LD_LIBRARY_PATH=/usr/local/lib
LOG=/data/local/dsh-daemon.log
PIDFILE=/data/local/dsh-daemon.pid
is_running() { [ -f \"\$PIDFILE\" ] && kill -0 \"\$(cat \$PIDFILE)\" 2>/dev/null; }
start_dsh() {
  echo \"[\$(date)] starting dsh bonio\" >> \$LOG
  nohup /usr/local/bin/dsh --profile bonio --port $WEB_PORT --no-open >> \$LOG 2>&1 &
  echo \$! > \$PIDFILE
}
stop_dsh() {
  if [ -f \"\$PIDFILE\" ]; then
    kill \"\$(cat \$PIDFILE)\" 2>/dev/null; sleep 3; kill -9 \"\$(cat \$PIDFILE)\" 2>/dev/null
    rm -f \$PIDFILE
  fi
}
case \"\$1\" in
  start) start_dsh ;;
  stop) stop_dsh ;;
  restart) stop_dsh; sleep 1; start_dsh ;;
  status) if is_running; then echo \"dsh running (pid \$(cat \$PIDFILE))\"; else echo \"dsh stopped\"; fi ;;
  *) while true; do if ! is_running; then start_dsh; fi; sleep 15; done ;;
esac
DAEMONEOF
  chmod 755 /data/local/bin/dsh-daemon.sh
"

log "Restarting daemon"
"$HDC" shell "
  HOME=$DEVICE_HOME LD_LIBRARY_PATH=/usr/local/lib nohup /data/local/bin/dsh-daemon.sh restart > /dev/null 2>&1 &
"

sleep 20
log "Verifying gateway"
"$HDC" shell "netstat -tlnp 2>/dev/null | grep -E '10724|$WEB_PORT' | head -3"

log "Done. From the host:"
log "  $HDC fport tcp:10724 tcp:10724"
log "  cd $BRIDGE_DIR/test && BRIDGE_TOKEN=$TOKEN node smoke-client.mjs chat"
