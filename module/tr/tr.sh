#!/system/bin/sh
# 免重启：解除有线充电温控降速（MCA charger_thermal/wired_thermal_remove）
D=/data/adb/mi_charge_boost; mkdir -p $D
CONF=$D/thermal_remove; LOG=$D/tr.log
node(){
  for n in /sys/class/xm_power/charger/charger_thermal/wired_thermal_remove \
           $(find -L /sys/class/xm_power -maxdepth 4 -name wired_thermal_remove -type f 2>/dev/null); do
    [ -f "$n" ] && { echo $n; return; }
  done
}
online(){ cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0; }
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 200 ] && sed -i '1,100d' $LOG; }
apply(){ # 按配置写节点；在线时先 0 后 1，复位驱动内部状态
  N=$(node); [ -z "$N" ] && return 1
  W=$(cat $CONF 2>/dev/null); [ "$W" = 1 ] || W=0
  chmod 0664 $N 2>/dev/null
  if [ "$W" = 1 ]; then echo 0 > $N 2>/dev/null; sleep 0.3; echo 1 > $N 2>/dev/null
  else echo 0 > $N 2>/dev/null; fi
  log "${SRC:-手动} 写入 $W（充电器在线=$(online)）"
}
case "$1" in
  status) N=$(node); C=-; [ -n "$N" ] && C=$(cat $N 2>/dev/null)
    W=$(cat $CONF 2>/dev/null); [ "$W" = 1 ] || W=0
    echo "{\"avail\":$([ -n "$N" ] && echo 1 || echo 0),\"want\":$W,\"cur\":\"$C\",\"online\":$(online)}";;
  set) [ "$2" = 1 ] && echo 1 > $CONF || echo 0 > $CONF; apply; sh $0 status;;
  apply) apply;;
  log) tail -n 30 $LOG 2>/dev/null || echo 暂无;;
  *) echo "用法: tr.sh status|set 0|1|apply|log";;
esac
