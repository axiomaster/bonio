#!/bin/bash
# =============================================================================
# deploy-bonio-wechat-ohos.sh — deploy the bonio-wechat dsh plugin to an OHOS
# device and wire it into the bonio profile.
#
# Modes:
#   wecom  (default) — WeCom intelligent-bot WebSocket
#   weixin           — personal WeChat via ilink HTTP
#
# Config comes from environment variables:
#   BONIO_WECHAT_MODE  (wecom|weixin)
#   WECOM_BOT_ID / WECOM_BOT_SECRET        (wecom mode)
#   WEIXIN_TOKEN / WEIXIN_BASE_URL         (weixin mode, base_url optional)
# =============================================================================
set -euo pipefail

HDC="${HDC:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WECHAT_DIR="$SCRIPT_DIR/../dsh-plugins/bonio-wechat"
DEVICE_HOME=/data/local/home
DSH_NM=/system/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules

log() { printf '\033[1;36m[deploy-wechat]\033[0m %s\n' "$*"; }

[ -x "$HDC" ] || { echo "hdc not found"; exit 1; }
"$HDC" list targets | grep -q . || { echo "no device"; exit 1; }

log "Packing bonio-wechat"
tar -czf /tmp/bonio-wechat.tgz -C "$WECHAT_DIR" build package.json cordis.patch.yml

log "Pushing to device"
"$HDC" file send /tmp/bonio-wechat.tgz /data/local/bonio-wechat.tgz

log "Extracting into dsh node_modules"
"$HDC" shell "
  mkdir -p $DSH_NM/@bonio/dsh-bonio-wechat
  cd $DSH_NM/@bonio/dsh-bonio-wechat
  tar -xzf /data/local/bonio-wechat.tgz
  find build -name '._*' -delete
"

log "Syncing into profile node_modules"
"$HDC" shell "
  mkdir -p $DEVICE_HOME/.dsh/profiles/bonio/node_modules/@bonio
  cp -r $DSH_NM/@bonio/dsh-bonio-wechat $DEVICE_HOME/.dsh/profiles/bonio/node_modules/@bonio/
  rm -rf $DEVICE_HOME/.dsh/profiles/bonio/node_modules/@bonio/dsh-bonio-wechat/src
"

log "Adding bundle to bonio profile"
"$HDC" shell "
  node -e '
    const fs = require(\"fs\");
    const p = \"$DEVICE_HOME/.dsh/profiles/bonio/package.json\";
    const j = JSON.parse(fs.readFileSync(p, \"utf8\"));
    const b = j.dsh.profile.bundles;
    if (!b.includes(\"@bonio/dsh-bonio-wechat\")) b.push(\"@bonio/dsh-bonio-wechat\");
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + \"\\n\");
    console.log(\"bundles:\", b.join(\", \"));
  '
"

log "Writing wechat config into profile patch"
MODE="${BONIO_WECHAT_MODE:-wecom}"
"$HDC" shell "grep -q 'bonio-wechat' $DEVICE_HOME/.dsh/profiles/bonio/cordis.patch.yml || cat >> $DEVICE_HOME/.dsh/profiles/bonio/cordis.patch.yml << EOF
- id: bonio-wechat
  config:
    mode: $MODE
    wecom:
      bot_id: \${WECOM_BOT_ID:-}
      bot_secret: \${WECOM_BOT_SECRET:-}
    weixin:
      token: \${WEIXIN_TOKEN:-}
      base_url: \${WEIXIN_BASE_URL:-https://ilinkai.weixin.qq.com}
    allow_from: []
EOF"

log "Restarting daemon"
"$HDC" shell "HOME=$DEVICE_HOME LD_LIBRARY_PATH=/usr/local/lib nohup /data/local/bin/dsh-daemon.sh restart > /dev/null 2>&1 &"

sleep 25
log "Verifying"
"$HDC" shell "grep -iE 'bonio-wechat|ilink|wecom' /data/local/dsh-daemon.log | tail -5"

log "Done. Set WECOM_BOT_ID/WECOM_BOT_SECRET (or WEIXIN_TOKEN) in the daemon env to activate."
