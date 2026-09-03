#!/bin/sh
# dsh bonio 常驻守护脚本：确保 dsh --profile bonio 始终运行。
# 由 tools/deploy-bonio-bridge-ohos.sh 推送到设备 /data/local/bin/。
export HOME=/data/local/home
# Keep this free of anco_hmos/chipset-sdk entries: they shadow system libs and
# break native /system binaries (cli_tool) with symbol relocation errors. Plain
# /usr/local/lib lets the loader fall back to the correct system defaults.
export LD_LIBRARY_PATH=/usr/local/lib
LOG=/data/local/dsh-daemon.log
PIDFILE=/data/local/dsh-daemon.pid
WEB_PORT=13082

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null
}

start_dsh() {
  echo "[$(date)] starting dsh bonio" >> $LOG
  nohup /usr/local/bin/dsh --profile bonio --port $WEB_PORT --no-open >> $LOG 2>&1 &
  echo $! > $PIDFILE
}

stop_dsh() {
  if [ -f "$PIDFILE" ]; then
    kill "$(cat $PIDFILE)" 2>/dev/null
    sleep 3
    kill -9 "$(cat $PIDFILE)" 2>/dev/null
    rm -f $PIDFILE
  fi
}

case "$1" in
  start) start_dsh ;;
  stop)  stop_dsh ;;
  restart) stop_dsh; sleep 1; start_dsh ;;
  status)
    if is_running; then echo "dsh running (pid $(cat $PIDFILE))"; else echo "dsh stopped"; fi
    ;;
  *)
    # 默认：保持运行（守护循环，15s 自愈）
    while true; do
      if ! is_running; then start_dsh; fi
      sleep 15
    done
    ;;
esac
