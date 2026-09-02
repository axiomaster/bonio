#!/bin/bash
# ============================================================================
# deploy-dsh-skills-ohos.sh — deploy bonio dsh skills (ohos-cli-tool,
# phone-use-harmonyos) to the on-device dsh skill root.
#
# Device dsh runs with HOME=/data/local/home so its user skill root is
# /data/local/home/.dsh/skills/<name>/SKILL.md. These device-adapted bundles
# invoke the CLIs directly (no hdc layer).
# ============================================================================
set -euo pipefail

HDC="${HDC:-/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVICE_SKILLS=/data/local/home/.dsh/skills

log() { printf '\033[1;36m[deploy-skills]\033[0m %s\n' "$*"; }

[ -x "$HDC" ] || { echo "hdc not found"; exit 1; }
"$HDC" list targets | grep -q . || { echo "no device"; exit 1; }

# 1) ohos-cli-tool — device-adapted SKILL.md + config schemas
WORK=$(mktemp -d)
mkdir -p "$WORK/ohos-cli-tool"
cp "$SCRIPT_DIR/skills-device/ohos-cli-tool-SKILL.md" "$WORK/ohos-cli-tool/SKILL.md"
cp -r "$REPO_ROOT/skills/ohos-cli-tool/configs" "$WORK/ohos-cli-tool/configs" 2>/dev/null || true
cp -r "$REPO_ROOT/skills/ohos-cli-tool/scripts" "$WORK/ohos-cli-tool/scripts" 2>/dev/null || true
cp "$REPO_ROOT/skills/ohos-cli-tool/REFERENCE.md" "$WORK/ohos-cli-tool/REFERENCE.md" 2>/dev/null || true

# 2) phone-use-harmonyos — device-adapted SKILL.md
mkdir -p "$WORK/phone-use-harmonyos"
cp "$SCRIPT_DIR/skills-device/phone-use-harmonyos-SKILL.md" "$WORK/phone-use-harmonyos/SKILL.md"
cp "$REPO_ROOT/skills/phone-use-harmonyos/config/phone-use-harmonyos.conf" "$WORK/phone-use-harmonyos/config/phone-use-harmonyos.conf" 2>/dev/null || true

# Pack and push
tar -czf "$WORK/dsh-skills.tgz" -C "$WORK" ohos-cli-tool phone-use-harmonyos
log "pushing skills bundle"
"$HDC" file send "$WORK/dsh-skills.tgz" /data/local/dsh-skills.tgz >/dev/null
"$HDC" shell "
  mkdir -p $DEVICE_SKILLS
  cd $DEVICE_SKILLS
  tar -xzf /data/local/dsh-skills.tgz
  rm -f /data/local/dsh-skills.tgz
  chmod -R a+r $DEVICE_SKILLS
  find $DEVICE_SKILLS -name '._*' -delete
  echo '--- installed ---'
  ls -la $DEVICE_SKILLS
"
rm -rf "$WORK"
log "restarting dsh to load skills..."
"$HDC" shell '/data/local/bin/dsh-daemon.sh restart' 2>&1 || true
log "done"
