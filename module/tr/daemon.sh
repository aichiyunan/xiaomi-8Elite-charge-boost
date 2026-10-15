#!/system/bin/sh
# 解除温控守护：插入充电器后重新下发；充电中被复位则补写
MODDIR=${0%/*}; T=$MODDIR/tr.sh
D=/data/adb/mi_charge_boost; CONF=$D/thermal_remove
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
last=0; n=0
while true; do
  sleep 3
  [ -f ${MODDIR%/tr}/disable ] && continue
  [ "$(cat $CONF 2>/dev/null)" = 1 ] || { last=$(cat /sys/class/power_supply/usb/online 2>/dev/null); continue; }
  on=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
  if [ "$on" = 1 ] && [ "$last" != 1 ]; then
    sleep 3; SRC=插入 sh $T apply; n=0
  elif [ "$on" = 1 ]; then
    n=$((n+1))
    if [ $n -ge 10 ]; then n=0
      c=$(sh $T status | sed 's/.*"cur":"\([^"]*\)".*/\1/')
      [ "$c" = 0 ] && SRC=补写 sh $T apply
    fi
  fi
  last=$on
done
