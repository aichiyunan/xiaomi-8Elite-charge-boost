#!/system/bin/sh
# 公版 PPS 解锁：拔出充电器时写 pd_verifed=1，下次插入第三方 PPS 头即放行高功率档
# 节点：酷安@低线阻狂魔、酷安@花橋桥；思路参考：酷安@瓦力喀 / FreePPS（本脚本为独立实现）
D=/data/adb/mi_charge_boost; mkdir -p $D
CONF=$D/pps; GOLD=$D/pps_gold; LOG=$D/pps.log
PV=/sys/class/qcom-battery/pd_verifed
PV2=/sys/class/Charging_Adapter/pd_adapter/usbpd_verifed
SVID=/sys/class/xm_power/typec/strategy_pd_auth/adapter_svid
APDO=/sys/class/xm_power/typec/apdo_max
node(){ for n in $PV $PV2; do [ -f $n ] && { echo $n; return; }; done; }
fp(){ [ -d /data/adb/modules/FreePPS ] && [ ! -f /data/adb/modules/FreePPS/disable ] && [ ! -f /data/adb/modules/FreePPS/remove ]; }
online(){ cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0; }
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 200 ] && sed -i '1,100d' $LOG; }
w(){ N=$(node); [ -n "$N" ] || return 1; chmod 0664 $N 2>/dev/null; echo $1 > $N 2>/dev/null; }
head_name(){ case "$1" in 0000) echo "公版 PPS（SVID 0000）";; 2717) echo "小米原装（MIPPS）";; ""|-) echo "--";; *) echo "其它（SVID $1）";; esac; }
case "$1" in
status) N=$(node); C=-; [ -n "$N" ] && C=$(cat $N 2>/dev/null)
  W=$(cat $CONF 2>/dev/null); [ "$W" = 1 ] || W=0; G=$(cat $GOLD 2>/dev/null); [ "$G" = 1 ] || G=0
  S=$(cat $SVID 2>/dev/null); A=$(cat $APDO 2>/dev/null)
  echo "{\"avail\":$([ -n "$N" ] && echo 1 || echo 0),\"want\":$W,\"gold\":$G,\"cur\":\"$C\",\"online\":$(online),\"svid\":\"$S\",\"head\":\"$(head_name "$S")\",\"apdo\":\"$A\",\"fp\":$(fp && echo 1 || echo 0)}";;
set) [ "$2" = 1 ] && echo 1 > $CONF || echo 0 > $CONF
  { [ -f $D/pps.pid ] && kill -0 $(cat $D/pps.pid) 2>/dev/null; } || nohup sh ${0%/*}/daemon.sh >/dev/null 2>&1 &
  if [ "$2" = 1 ]; then
    if fp; then log "已安装 FreePPS，本模块 PPS 解锁停用"
    elif [ "$(online)" = 1 ]; then log "已开启，拔出充电器后放行，下次插入生效"
    else w 1 && log "已开启，写入 pd_verifed=1，下次插入生效"; fi
  else log "已关闭（下次拔插后恢复系统默认）"; fi
  sh ${0%/*}/../dtbo/apply.sh desc >/dev/null 2>&1; sh $0 status;;
gold) [ "$2" = 1 ] && echo 1 > $GOLD || echo 0 > $GOLD; log "金标动画 $([ "$2" = 1 ] && echo 开 || echo 关)"; sh $0 status;;
lock) w 1;;
unplug) if [ "$(cat $D/pps_head 2>/dev/null)" = 2717 ]; then w 0; log "拔出小米原装头，pd_verifed 保持 0，不干扰原装私有协议认证（插一次公版头后恢复放行）"
  else w 1 && log "拔出充电器，写入 pd_verifed=1"; fi;;
plug) S=$(cat $SVID 2>/dev/null); [ -n "$S" ] && echo "$S" > $D/pps_head; A=$(cat $APDO 2>/dev/null); V=$(cat $(node) 2>/dev/null)
  log "插入$(head_name "$S")，apdo_max=${A:-?}W，pd_verifed=$V$([ "$S" = 0000 ] && [ "$V" = 1 ] && echo "，已放行")"
  [ "$S" = 0000 ] && [ "$V" = 1 ] && [ -n "$A" ] && echo $A > $D/pps_last;;
burst) # 金标动画：公版头 + 已放行 + VBUS 升到 12V 以上时，给 SystemUI 发快充广播
  t=0; while [ $t -lt 20 ]; do
    [ "$(cat $(node) 2>/dev/null)" = 1 ] && [ "$(cat $SVID 2>/dev/null)" = 0000 ] && [ "$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null || echo 0)" -ge 12000000 ] && break
    sleep 0.1; t=$((t+1)); done
  [ $t -ge 20 ] && exit 0
  A=$(cat $APDO 2>/dev/null); case "$A" in ''|*[!0-9]*) P=100;; *) [ $A -ge 90 ] && P=100 || P=$A;; esac
  b(){ am broadcast -p com.android.systemui -a miui.intent.action.ACTION_QUICK_CHARGE_TYPE --ei miui.intent.extra.quick_charge_type $1 --ei miui.intent.extra.POWER_MAX $P --ei miui.intent.extra.CAR_CHARGE 0 >/dev/null 2>&1; }
  b 1; sleep 0.1
  am broadcast -p com.android.systemui -a miui.intent.action.ACTION_SOC_DECIMAL --ei miui.intent.extra.soc_decimal 0 --ei miui.intent.extra.soc_decimal_rate 0 >/dev/null 2>&1; sleep 0.1
  b 4; sleep 0.25; b 4; sleep 0.4; b 4; log "金标动画 ${P}W";;
log) tail -n 30 $LOG 2>/dev/null || echo 暂无;;
*) echo "用法: pps.sh status|set 0|1|gold 0|1|log";;
esac
