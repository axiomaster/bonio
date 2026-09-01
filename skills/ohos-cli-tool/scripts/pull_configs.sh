#!/bin/bash
HDC="/Users/ohci/tools/ohos-command-line-tools/sdk/default/openharmony/toolchains/hdc"
cd "/Users/ohci/code/bonio/skills/ohos-cli-tool"
FILES=$($HDC shell ls /system/bin/cli_tool/configs/)
for f in $FILES; do
  if $HDC file recv /system/bin/cli_tool/configs/$f configs/$f >/dev/null 2>&1; then
    echo "OK $f"
  else
    echo "FAIL $f"
  fi
done
