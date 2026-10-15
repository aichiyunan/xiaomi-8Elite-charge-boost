#!/system/bin/sh
# 公版 PPS 守护：拔出时写 pd_verifed=1；充电中认到公版头（SVID 0000）被清 0 就马上锁回 1，小米原装头（2717）完全不碰
MODDIR=${0%/*}; P=$MODDIR/pps.sh; D=/data/adb/mi_charge_boost
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
if [ -f $D/pps.pid ] && kill -0 $(cat $D/pps.pid) 2>/dev/null; then exit 0; fi
echo $$ > $D/pps.pid
fp(){ [ -d /data/adb/modules/FreePPS ] && [ ! -f /data/adb/modules/FreePPS/disable ] && [ ! -f /data/adb/modules/FreePPS/remove ]; }
SVID=/sys/class/xm_power/typec/strategy_pd_auth/adapter_svid
PVN=/sys/class/qcom-battery/pd_verifed; [ -f $PVN ] || PVN=/sys/class/Charging_Adapter/pd_adapter/usbpd_verifed
lk=0; lkn=0
last=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
[ "$(cat $D/pps 2>/dev/null)" = 1 ] && [ "$last" != 1 ] && ! fp && sh $P unplug
[ "$(cat $D/pps 2>/dev/null)" = 1 ] || { [ "$(cat $D/pps_head 2>/dev/null)" = 2717 ] && echo 0 > /sys/class/qcom-battery/pd_verifed 2>/dev/null; }
while true; do
  if [ -f ${MODDIR%/pps}/disable ] || [ "$(cat $D/pps 2>/dev/null)" != 1 ] || fp; then
    last=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0); sleep 5; continue; fi
  on=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
  if [ "$on" = 1 ] && [ "$last" != 1 ]; then
    lk=0; lkn=0
    [ "$(cat $D/pps_gold 2>/dev/null)" = 1 ] && sh $P burst &
    (sleep 3; sh $P plug) &
  elif [ "$on" = 1 ]; then
    # 充电中按充电头区分：公版头（SVID 0000）pd_verifed 被内核清 0 就马上写回 1；小米原装头（2717）或未识别完全不碰
    if [ "$(cat $SVID 2>/dev/null)" = 0000 ] && [ "$(cat $PVN 2>/dev/null)" = 0 ]; then
      sh $P lock; lkn=$((lkn+1)); [ $lk = 0 ] && { lk=1; echo "$(date '+%m-%d %H:%M:%S') 公版头 pd_verifed 被清 0，已锁回 1" >> $D/pps.log; }
    fi
  elif [ "$on" != 1 ] && [ "$last" = 1 ]; then
    [ $lkn -gt 1 ] && echo "$(date '+%m-%d %H:%M:%S') 本次充电共锁回 $lkn 次" >> $D/pps.log
    sh $P unplug; sh ${MODDIR%/pps}/dtbo/apply.sh desc >/dev/null 2>&1
  fi
  last=$on
  sleep 0.5
done
