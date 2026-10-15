#!/system/bin/sh
# 小米私有协议功率（dtbo，重启生效）：proto.sh status | set 0|100|120
# 参考 K80 Pro 原厂 dtbo：mca_protocol_pd_class/max_power 120、mca_strategy_quick_charge/max_power 120000
D=/data/adb/mi_charge_boost; mkdir -p $D
PF=${PROTO_F:-$D/proto}; LOG=$D/proto.log
AP=${0%/*}/../dtbo/apply.sh
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 100 ] && sed -i '1,50d' $LOG; }
want(){ w=$(cat $PF 2>/dev/null); case "$w" in 100|120) echo $w;; *) echo 0;; esac; }
case "$1" in
status)
  set -- $(sh $AP status 2>/dev/null); st=${1:-none}; ap=0
  [ "$st" = mod ] && case "$6" in 100|120) ap=$6;; esac
  S=$(getprop ro.boot.slot_suffix); DD=$D/dtbo; [ -f /data/adb/.mcb_dtbo/stock.img ] && DD=/data/adb/.mcb_dtbo
  bt=$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) )); wt=$(stat -c %Y $DD/written$S 2>/dev/null || echo 0)
  pend=0; [ "$wt" -gt "$bt" ] && pend=1
  echo "{\"want\":$(want),\"applied\":$ap,\"state\":\"$st\",\"pending\":$pend}";;
set)
  case "$2" in 100|120) echo $2 > $PF;; *) rm -f $PF;; esac
  set -- $(sh $AP status 2>/dev/null)
  if [ "$1" = mod ]; then a="${2:--} ${3:--} ${4:--} ${5:--}"; else a="- - - -"; fi
  LL=$D/proto_last.log; echo "[$(date '+%m-%d %H:%M:%S')]" > $LL
  if [ "$(want)" = 0 ] && [ "$a" = "- - - -" ]; then
    if [ "$1" = mod ]; then sh $AP restore >> $LL 2>&1; r=$?; else echo "- 私有协议已恢复原厂 90W" >> $LL; r=0; fi
  else sh $AP $a >> $LL 2>&1; r=$?; fi
  cat $LL
  log "私有协议 $( [ "$(want)" = 0 ] && echo 原厂90W || echo $(want)W ) 结果 rc=$r"
  exit $r;;
log) if [ -s $D/proto_last.log ]; then cat $D/proto_last.log; else tail -n 20 $LOG 2>/dev/null || echo 暂无记录; fi;;
*) echo "用法: proto.sh status|set 0|100|120|log";;
esac
