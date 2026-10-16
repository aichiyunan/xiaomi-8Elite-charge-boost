#!/system/bin/sh
# 实时充电电流守护：充电中每 2 秒检查，被系统温控改写就补写回设定值
MODDIR=${0%/*}; T=$MODDIR/cc.sh
D=/data/adb/mi_charge_boost; CONF=$D/cc; LOG=$D/cc.log
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 200 ] && sed -i '1,100d' $LOG; }
N=/sys/class/xm_power/charger/charger_thermal/wired_chg_curr
[ -f $N ] || N=$(find -L /sys/class/xm_power -maxdepth 4 -name wired_chg_curr -type f 2>/dev/null | head -1)
# 本机没有 MCA 温控电流节点（非小米 MCA 机型/内核不同）：守护不运行，WebUI 显示不支持
[ -n "$N" ] || { log "未找到 wired_chg_curr 节点，实时充电电流守护不启动"; exit 0; }
last=0; fix=0; was=0; off=0
while true; do
  sleep 2
  if [ -f ${MODDIR%/cc}/disable ]; then [ $was = 1 ] && { sh $T release; was=0; }; continue; fi
  read EN MA < $CONF 2>/dev/null; [ "$EN" = 1 ] || { [ -f $D/cc_stop ] && sh $T cutchk; was=0; last=$(cat /sys/class/power_supply/usb/online 2>/dev/null); continue; }
  was=1
  sh $T cutchk
  on=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
  [ -f $D/cc_stop ] && { last=1; continue; }   # 断充中：停充可能让 online 变 0，不当作拔出
  if [ "$on" = 1 ]; then
    [ "$last" != 1 ] && { pt=$(cut -d. -f1 /proc/uptime); fix=0; read _e AM < $D/cc_act 2>/dev/null; log "插入充电器，下发上限 ${AM:-$MA}mA"; }
    [ $(( $(cut -d. -f1 /proc/uptime) - ${pt:-0} )) -lt 20 ] && { last=$on; continue; }   # 插入 20 秒内不写节点，让协议认证和电荷泵爬升先完成
    pl=$(cat $D/cc_lvl 2>/dev/null || echo 0)
    tg=$(CC_LIB=1 sh $T target); want=$((tg*1000)); c=$(cat $N 2>/dev/null)
    nl=$(cat $D/cc_lvl 2>/dev/null || echo 0)
    [ "$nl" != "$pl" ] && log "温控墙档位 $pl→$nl，上限 ${tg}mA"
    if [ "$c" != "$want" ]; then
      chmod 0666 $N 2>/dev/null; echo $want > $N 2>/dev/null
      if [ "$nl" = "$pl" ]; then fix=$((fix+1)); echo $fix > $D/cc_fix
        [ $fix -le 3 ] || [ $((fix%50)) = 0 ] && log "被改为 $((c/1000))mA，补写 ${tg}mA（本次第 $fix 次）"; fi
    fi
  else
    now=$(date +%s); [ "$last" = 1 ] && { log "拔出充电器（本次补写 $fix 次）"; off=$now; }
    read _e AM < $D/cc_act 2>/dev/null
    if [ $((now-off)) -ge 3 ]; then
      [ "$AM" != "$MA" ] && { sh $T sync; log "新上限 ${MA}mA 已生效（原 ${AM:-?}mA）"; }
      [ -f $D/cc_wall ] && [ "$(cat $D/cc_wall)" != "$(cat $D/cc_wall_act 2>/dev/null)" ] && { cp -f $D/cc_wall $D/cc_wall_act; log "新的断充温控墙设定已生效"; }
    fi
  fi
  last=$on
done
