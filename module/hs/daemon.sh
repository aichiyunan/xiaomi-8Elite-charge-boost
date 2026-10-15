#!/system/bin/sh
# 原装头握手失败自动重试（实验性，默认关）：插入 20 秒后仍在 PD 普通充电（VBUS<11V、电荷泵没起来），
# 用 input_suspend 1→0 让系统重走一次充电策略/协议认证；每次插入最多重试 2 次。开关 $D/hs
MODDIR=${0%/*}; D=/data/adb/mi_charge_boost; LOG=$D/hs.log
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
if [ -f $D/hs.pid ] && kill -0 $(cat $D/hs.pid) 2>/dev/null; then exit 0; fi
echo $$ > $D/hs.pid
X=/sys/class/xm_power
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 200 ] && sed -i '1,100d' $LOG; }
SN=""; for n in $X/charger/charge_interface/input_suspend /sys/class/power_supply/battery/input_suspend; do [ -f $n ] && { SN=$n; break; }; done
last=0; t0=0; tries=0
while true; do
  sleep 2
  on=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
  [ -f $D/cc_stop ] && { last=$on; continue; }
  if [ "$on" = 1 ]; then
    now=$(cut -d. -f1 /proc/uptime)
    [ "$last" != 1 ] && { t0=$now; tries=0; }
    if [ "$(cat $D/hs 2>/dev/null)" = 1 ] && [ ! -f ${MODDIR%/hs}/disable ] && [ -n "$SN" ] && [ $tries -lt 2 ] && [ $((now-t0)) -ge 20 ]; then
      v=$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null || echo 0); rt=$(cat $X/charger/charger_common/real_type 2>/dev/null)
      soc=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 100); sv=$(cat $X/typec/strategy_pd_auth/adapter_svid 2>/dev/null)
      pv=$(cat /sys/class/qcom-battery/pd_verifed 2>/dev/null)
      case "$rt" in *PD*|*NonStandard*|*Unknown*) pd=1;; *) pd=0;; esac
      if [ $pd = 1 ] && [ "$v" -lt 11000000 ] && [ "$soc" -lt 85 ]; then
        tries=$((tries+1)); log "握手失败（$rt，VBUS $((v/1000))mV，SVID ${sv:--}，pd_verifed ${pv:--}），第 $tries 次重试"
        echo 1 > $SN 2>/dev/null; sleep 2; echo 0 > $SN 2>/dev/null; t0=$now
        sleep 18; v=$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null || echo 0)
        log "重试后 VBUS $((v/1000))mV，$([ "$v" -ge 11000000 ] && echo 快充已恢复 || echo 仍未进快充)"
        t0=$(cut -d. -f1 /proc/uptime)
      fi
    fi
  fi
  last=$on
done
