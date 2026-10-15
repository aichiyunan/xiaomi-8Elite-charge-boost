#!/system/bin/sh
# 实时充电电流（免重启）：写 MCA charger_thermal/wired_chg_curr（单位 uA），充电中改动即时生效
# 配置 $D/cc: "<开关0|1> <电流mA>"
D=/data/adb/mi_charge_boost; mkdir -p $D
CONF=$D/cc; LOG=$D/cc.log
MIN=1000; REL=22000
# 上限跟随 DTBO 已写入的快充电流（未修改/已还原按原厂 15500）
dmax(){ S=$(getprop ro.boot.slot_suffix 2>/dev/null); x=/data/adb/mi_charge_boost/dtbo; [ -f /data/adb/.mcb_dtbo/stock.img ] && x=/data/adb/.mcb_dtbo
  i=""; [ "$(cat $x/state$S 2>/dev/null)" = mod ] && [ -f $x/conf ] && read i _r < $x/conf
  case "$i" in ''|-|*[!0-9]*) i=15500;; esac; [ $i -gt $REL ] && i=$REL; [ $i -lt $MIN ] && i=$MIN; echo $i; }
# 断充温度上限跟随 DTBO 写入的满速/断充温度（未改 DTBO 为 58°C）
tmax(){ S=$(getprop ro.boot.slot_suffix 2>/dev/null); x=/data/adb/mi_charge_boost/dtbo; [ -f /data/adb/.mcb_dtbo/stock.img ] && x=/data/adb/.mcb_dtbo
  t=""; [ "$(cat $x/state$S 2>/dev/null)" = mod ] && [ -f $x/conf ] && read _i _v t _r < $x/conf
  case "$t" in ''|-|*[!0-9]*) t=58;; esac; [ $t -gt 58 ] && t=58; [ $t -lt 40 ] && t=40; echo $t; }
MAX=$(dmax); DEF=$MAX; TMAX=$(tmax)
node(){ for n in /sys/class/xm_power/charger/charger_thermal/wired_chg_curr \
    $(find -L /sys/class/xm_power -maxdepth 4 -name wired_chg_curr -type f 2>/dev/null); do
    [ -f "$n" ] && { echo $n; return; }; done; }
online(){ cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0; }
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 200 ] && sed -i '1,100d' $LOG; }
conf(){ EN=0; MA=$DEF; [ -f $CONF ] && read EN MA < $CONF; [ "$EN" = 1 ] || EN=0
  case "$MA" in ''|*[!0-9]*) MA=$DEF;; esac; [ $MA -lt $MIN ] && MA=$MIN; [ $MA -gt $MAX ] && MA=$MAX; }
# 实际生效的配置：充电中调节只改 $CONF / $D/cc_wall，拔出充电器 3 秒后由守护进程同步到 *_act
act(){ AMA=""; [ -f $D/cc_act ] && read _e AMA < $D/cc_act; case "$AMA" in ''|*[!0-9]*) AMA=$MA;; esac
  [ $AMA -gt $MAX ] && AMA=$MAX; [ $AMA -lt $MIN ] && AMA=$MIN; }
sync(){ conf; echo "$EN $MA" > $D/cc_act; [ -f $D/cc_wall ] && cp -f $D/cc_wall $D/cc_wall_act; }
wr(){ N=$(node); [ -n "$N" ] || return 1; chmod 0666 $N 2>/dev/null; echo $1 > $N 2>/dev/null; }
cur(){ N=$(node); [ -n "$N" ] && cat $N 2>/dev/null; }
# 断充温控墙 "<总开关> <限流开关> <T1> <C1> <T2> <C2> <断充温度>"（旧 5 项格式自动兼容）
wparse(){ WE=0; LIM=0; T1=42; C1=12000; T2=46; C2=6000; T3=54; [ -f "$1" ] || return 0
  set -- $(cat "$1"); if [ $# -le 5 ]; then WE=${1:-0}; LIM=$WE; T1=${2:-42}; C1=${3:-12000}; T2=${4:-46}; C2=${5:-6000}
  else WE=$1; LIM=$2; T1=$3; C1=$4; T2=$5; C2=$6; T3=${7:-54}; fi
  [ "$WE" = 1 ] || WE=0; [ "$LIM" = 1 ] || LIM=0
  for v in T1 C1 T2 C2 T3; do eval x=\$$v; case "$x" in ''|*[!0-9]*) WE=0; LIM=0;; esac; done
  [ $WE = 1 ] || return 0
  [ $T3 -lt 40 ] && T3=40; [ $T3 -gt $TMAX ] && T3=$TMAX
  for v in C1 C2; do eval x=\$$v; [ $x -gt $MAX ] && eval $v=$MAX; [ $x -lt $MIN ] && eval $v=$MIN; done
  [ $T2 -lt $T1 ] && { x=$T1; T1=$T2; T2=$x; x=$C1; C1=$C2; C2=$x; }; }
wconf(){ wparse $D/cc_wall; }                                   # 设定值
wact(){ if [ -f $D/cc_wall_act ]; then wparse $D/cc_wall_act; else wconf; fi; }   # 生效值
wline(){ echo "$WE $LIM $T1 $C1 $T2 $C2 $T3"; }
# 温度（0.1°C）：软断充伪装时用真实温度
temp(){ t=$(cat /sys/class/power_supply/battery/temp 2>/dev/null); case "$t" in ''|*[!0-9-]*) t=0;; esac; echo $t; }
snode(){ for n in /sys/class/xm_power/charger/charge_interface/input_suspend $(find -L /sys/class/xm_power -maxdepth 4 -name input_suspend -type f 2>/dev/null) /sys/class/power_supply/battery/input_suspend; do [ -f "$n" ] && { echo $n; return; }; done; }
suspend(){ n=$(snode); [ -n "$n" ] || return 1; chmod 0666 $n 2>/dev/null; echo $1 > $n 2>/dev/null; }
# 断充：到 T3 停充（input_suspend=1），降 3°C 或关闭开关时恢复；状态记在 $D/cc_stop
cutchk(){ conf; wact; t=$(temp)
  if [ $EN = 1 ] && [ $WE = 1 ]; then
    if [ ! -f $D/cc_stop ] && [ $t -ge $((T3*10)) ]; then suspend 1 && { touch $D/cc_stop; log "电池 $((t/10)).$((t%10))°C ≥ ${T3}°C，断充"; }
    elif [ -f $D/cc_stop ] && [ $t -le $((T3*10-30)) ]; then suspend 0; rm -f $D/cc_stop; log "降到 $((t/10)).$((t%10))°C，恢复充电"; fi
  elif [ -f $D/cc_stop ]; then suspend 0; rm -f $D/cc_stop; log "断充温控墙已关闭，恢复充电"; fi; }
# 当前应写的上限 mA（温控墙带 1°C 回差，档位记在 $D/cc_lvl）
target(){ conf; act; wact; L=0; T=$AMA
  if [ $WE = 1 ] && [ $LIM = 1 ]; then t=$(temp); P=$(cat $D/cc_lvl 2>/dev/null || echo 0)
    if [ $t -ge $((T2*10)) ] || { [ "$P" = 2 ] && [ $t -gt $((T2*10-10)) ]; }; then L=2
    elif [ $t -ge $((T1*10)) ] || { [ "$P" -ge 1 ] && [ $t -gt $((T1*10-10)) ]; }; then L=1; fi
    [ $L = 1 ] && [ $C1 -lt $T ] && T=$C1; [ $L = 2 ] && [ $C2 -lt $T ] && T=$C2
  fi; echo $L > $D/cc_lvl; echo $T; }
apply(){ conf; [ $EN = 1 ] || return 0; wr $(($(target)*1000)); }
release(){ wr $((REL*1000)); [ -f $D/cc_stop ] && { suspend 0; rm -f $D/cc_stop; }; }   # 交还系统温控：写回最大值，之后由系统按温度下发
status(){ conf; act; wact; AW=$(wline); wconf; PD=0; [ $EN = 1 ] && [ $AMA != $MA ] && PD=1
  [ $EN = 1 ] && [ "$AW" != "$(wline)" ] && PD=1; N=$(node); c=$(cur); i=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
  echo "{\"avail\":$([ -n "$N" ] && echo 1 || echo 0),\"en\":$EN,\"ma\":$MA,\"max\":$MAX,\"act\":$AMA,\"pend\":$PD,\"cur\":\"$c\",\"ibat\":\"$i\",\"online\":$(online),\"fix\":\"$(cat $D/cc_fix 2>/dev/null)\",\"we\":$WE,\"lim\":$LIM,\"t3\":$T3,\"tmax\":$TMAX,\"stop\":$([ -f $D/cc_stop ] && echo 1 || echo 0),\"wact\":\"$AW\",\"t1\":$T1,\"c1\":$C1,\"t2\":$T2,\"c2\":$C2,\"lvl\":\"$(cat $D/cc_lvl 2>/dev/null)\",\"temp\":\"$(temp)\"}"; }
case "$1" in
  status) status;;
  set) conf; OE=$EN; [ "$2" = 1 ] && EN=1 || EN=0; echo "$EN ${3:-$DEF}" > $CONF; conf; echo "$EN $MA" > $CONF
       if [ $EN = 1 ] && [ $OE = 1 ] && [ "$(online)" = 1 ]; then act
         [ $AMA != $MA ] && log "充电中改为 ${MA}mA，拔出充电器 3 秒后生效（当前仍 ${AMA}mA）"
       else sync; echo 0 > $D/cc_fix
         if [ $EN = 1 ]; then apply; log "开启，上限 ${MA}mA（充电器在线=$(online)）"
         else release; log "关闭，交还系统温控"; fi; fi; status;;
  sync) sync; apply;;
  wall) shift; echo "$*" > $D/cc_wall; wconf; wline > $D/cc_wall; conf
        m="断充温控墙$([ $WE = 1 ] && echo "开：${T3}°C 断充，限流$([ $LIM = 1 ] && echo "开 ${T1}°C→${C1}mA ${T2}°C→${C2}mA" || echo 关)" || echo 关)"
        if [ $EN = 1 ] && [ "$(online)" = 1 ] && [ "$(cat $D/cc_wall_act 2>/dev/null)" != "$(wline)" ]; then log "充电中设定$m，拔出充电器 3 秒后生效"
        else cp -f $D/cc_wall $D/cc_wall_act; log "$m"; apply; cutchk; fi; status;;
  cutchk) cutchk;;
  target) target;;
  apply) apply;;
  release) release;;
  log) tail -n 40 $LOG 2>/dev/null || echo 暂无;;
  *) echo "用法: cc.sh status|set 0|1 <mA>|wall WE LIM T1 C1 T2 C2 T3|apply|release|log";;
esac
