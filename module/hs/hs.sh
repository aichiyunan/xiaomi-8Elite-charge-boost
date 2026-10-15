#!/system/bin/sh
D=/data/adb/mi_charge_boost; mkdir -p $D
case "$1" in
status) echo "{\"want\":$([ "$(cat $D/hs 2>/dev/null)" = 1 ] && echo 1 || echo 0)}";;
set) [ "$2" = 1 ] && echo 1 > $D/hs || echo 0 > $D/hs
  { [ -f $D/hs.pid ] && kill -0 $(cat $D/hs.pid) 2>/dev/null; } || nohup sh ${0%/*}/daemon.sh >/dev/null 2>&1 &
  echo "$(date '+%m-%d %H:%M:%S') 自动重试握手$([ "$2" = 1 ] && echo 开 || echo 关)" >> $D/hs.log; sh $0 status;;
log) tail -n 20 $D/hs.log 2>/dev/null || echo 暂无;;
esac
