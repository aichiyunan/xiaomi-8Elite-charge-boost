#!/system/bin/sh
# 低电量延迟关机：电量锁定 2%，完全屏蔽系统 0% 关机和小米 30 秒关机倒计时，
# 电池电压连续低于设定值后直接关机（不弹倒计时）
MODDIR=${0%/*}
. $MODDIR/common.sh
# 关机电压下限 = DTBO 内核关机电压（已写入的修改值，未修改则用本机原厂值）；低于它内核会先关机，设了也没用
vfloor(){ set -- $(sh $MODDIR/dtbo/apply.sh status 2>/dev/null)
  if [ "$1" = mod ] && [ -n "$3" ]; then VF=$3; else VF=$(sh $MODDIR/model.sh 2>/dev/null | sed -n 's/.*"v0":\([0-9]*\).*/\1/p'); fi
  case "$VF" in ''|*[!0-9]*) VF=2700;; esac; [ "$VF" -gt 3400 ] && VF=3400; }
[ "$1" = floor ] && { vfloor; echo $VF; exit 0; }
if [ -f $D/lowbat.pid ] && kill -0 $(cat $D/lowbat.pid) 2>/dev/null; then exit 0; fi
echo $$ > $D/lowbat.pid
find_ps
held=0; low=0; en_off=0; lt5=0
vfloor
# 写入当前放电日志（logger.sh 负责开 / 结束放电日志）
dl(){ f=$(cat $D/dcurrent 2>/dev/null); [ -n "$f" ] && [ -f $D/dlogs/$f ] && echo "[$(date '+%H:%M:%S')] [低电量] $*" >> $D/dlogs/$f; }
# 小米 shutdown_delay 节点：置 1 时系统弹出 30 秒关机倒计时；*_en 是功能开关
scan_sd(){
  SD=""; SDE=""
  for f in $BAT/shutdown_delay /sys/class/power_supply/bms/shutdown_delay /sys/class/qcom-battery/shutdown_delay \
           $(find -L /sys/class/xm_power /sys/class/qcom-battery -maxdepth 4 -name "*shutdown_delay*" -type f 2>/dev/null); do
    [ -f "$f" ] || continue
    case " $SD $SDE " in *" $f "*) continue;; esac
    case "$f" in *_en|*_enable) SDE="$SDE $f";; *) SD="$SD $f";; esac
  done
}
scan_sd
# 关掉倒计时功能开关，首次关之前记下原值，停用功能时还原
sde_off(){
  for f in $SDE; do
    grep -q "^$f|" $D/sde.list 2>/dev/null || echo "$f|$(cat $f 2>/dev/null)" >> $D/sde.list
    o=$(cat $f 2>/dev/null); [ "$o" = "0" ] || { echo 0 > $f 2>/dev/null; dl "倒计时开关 ${f##*/}=$o，已关闭（写入后 $(cat $f 2>/dev/null)）"; }
  done; en_off=1
}
sde_restore(){
  [ -f $D/sde.list ] || { en_off=0; return; }
  while IFS='|' read -r f v; do [ -f "$f" ] && [ -n "$v" ] && echo "$v" > "$f" 2>/dev/null; done < $D/sde.list
  rm -f $D/sde.list; en_off=0
}
block_sd(){ for f in $SD; do o=$(cat $f 2>/dev/null); [ "$o" = "0" ] || { echo 0 > $f 2>/dev/null; dl "$f=$o，系统要弹 30 秒倒计时，已清 0（写入后 $(cat $f 2>/dev/null)）"; }; done; }
release(){ [ $held = 1 ] && { dumpsys battery reset >/dev/null 2>&1; dl "解除 2% 锁定（${1:-电量回升}，真实电量 ${cap:-?}%）"; }; held=0; low=0; }
off_now(){
  echo "$(date +%s),$1" >> $D/shutdown.log
  dl "电压 ${1}mV 连续 3 次 ≤ 关机电压 ${MV}mV，直接关机（sys.powerctl shutdown）"
  sync
  # 直接走内核关机，不经过系统关机对话框和倒计时
  setprop sys.powerctl shutdown; sleep 5
  reboot -p 2>/dev/null; sleep 5
  svc power shutdown 2>/dev/null; sleep 30
}
while true; do
  MV=$(cat $D/shutdown_mv 2>/dev/null); [ -n "$MV" ] || MV=2800
  [ "$MV" -gt 0 ] 2>/dev/null && { [ "$MV" -lt $VF ] && MV=$VF; [ "$MV" -gt 3400 ] && MV=3400; }
  if [ "$MV" = "0" ] || [ -z "$BAT" ]; then release; sde_restore; sleep 60; find_ps; scan_sd; continue; fi
  sde_off
  cap=$(cat $BAT/capacity 2>/dev/null); st=$(cat $BAT/status 2>/dev/null)
  uv=$(cat $BAT/voltage_now 2>/dev/null); [ -n "$uv" ] || { sleep 30; continue; }
  if [ "$uv" -gt 100000 ]; then mv=$((uv/1000)); else mv=$uv; fi
  if [ "$st" = "Charging" ] || [ "$st" = "Full" ]; then release 开始充电; sleep 30; continue; fi
  # 未充电且电量 ≤10%：持续把倒计时标志清 0，系统就不会弹 30 秒关机提示
  [ "${cap:-100}" -le 10 ] && block_sd
  if [ "${cap:-100}" -ge 3 ]; then
    release
    if [ "${cap:-100}" -le 5 ]; then sleep 1; elif [ "${cap:-100}" -le 10 ]; then sleep 5; else sleep 30; fi
    continue
  fi
  # 电量 ≤2% 且未充电：系统显示电量锁定在 2%
  if [ "$mv" -gt "$MV" ]; then
    low=0
    [ $held = 0 ] && { dumpsys battery set level 2 >/dev/null 2>&1; held=1; dl "真实电量 ${cap}%，系统电量锁定 2%（电压 ${mv}mV，关机电压 ${MV}mV）"; }
  else
    # 连续 3 次（约 3 秒）低于设定值才关机，避免瞬时负载压降误判
    low=$((low+1)); dl "电压 ${mv}mV ≤ ${MV}mV（第 $low/3 次）"
    [ $low -ge 3 ] && off_now $mv
  fi
  sleep 1
done
