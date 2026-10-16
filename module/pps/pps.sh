#!/system/bin/sh
# 公版 PPS 解锁（v8.5.3）：PPS 逻辑由内置 FreePPS v1.7.0 执行（Seyud / 酷安@瓦力喀，GPL-3.0，
# https://github.com/Seyud/FreePPS，只改了路径，见 freepps-paths.patch 与 README-FreePPS.txt）。
# 本脚本只做开关映射（$D/pps → FreePPS 的 free 文件 1/0）、状态读取、只读日志；不写 pd_verifed。
# 节点：酷安@低线阻狂魔、酷安@花橋桥
D=${PPS_DATA:-/data/adb/mi_charge_boost}; mkdir -p $D
CONF=$D/pps; LOG=$D/pps.log; F=$D/freepps; MODROOT=${0%/*}; MODROOT=${MODROOT%/pps}
S0=${PPS_SYS:-}; MODS=${PPS_MODS:-/data/adb/modules}
PV=$S0/sys/class/qcom-battery/pd_verifed
PV2=$S0/sys/class/Charging_Adapter/pd_adapter/usbpd_verifed
SVID=$S0/sys/class/xm_power/typec/strategy_pd_auth/adapter_svid
APDO=$S0/sys/class/xm_power/typec/apdo_max
PMAX=$S0/sys/class/xm_power/charger/charger_common/power_max
RTYPE=$S0/sys/class/xm_power/charger/charger_common/real_type
BST=$S0/sys/class/power_supply/battery/status
USB=$S0/sys/class/power_supply/usb
node(){ for n in $PV $PV2; do [ -f $n ] && { echo $n; return; }; done; }
fp(){ [ -d $MODS/FreePPS ] && [ ! -f $MODS/FreePPS/disable ] && [ ! -f $MODS/FreePPS/remove ]; }
online(){ cat $USB/online 2>/dev/null || echo 0; }
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 300 ] && sed -i '1,150d' $LOG; }
running(){ [ -f $D/pps.pid ] && kill -0 $(cat $D/pps.pid) 2>/dev/null; }
head_name(){ case "$1" in 0000) echo "公版 PPS（SVID 0000）";; 2717) X=$(cat $PMAX 2>/dev/null); case "$X" in ""|0|*[!0-9]*) echo "小米原装（私有协议）";; *) echo "小米原装（私有协议 ${X}W）";; esac;; ""|-) echo "--";; *) echo "其它（SVID $1）";; esac; }
case "$1" in
status) N=$(node); C=-; [ -n "$N" ] && C=$(cat $N 2>/dev/null)
  W=$(cat $CONF 2>/dev/null); [ "$W" = 1 ] || W=0
  S=$(cat $SVID 2>/dev/null); A=$(cat $APDO 2>/dev/null); M=-; running && M=$(cut -d' ' -f1,2,3 $D/pps.mode 2>/dev/null)
  FR=$(cat $F/free 2>/dev/null)
  echo "{\"avail\":$([ -n "$N" ] && echo 1 || echo 0),\"want\":$W,\"free\":\"$FR\",\"cur\":\"$C\",\"online\":$(online),\"svid\":\"$S\",\"head\":\"$(head_name "$S")\",\"apdo\":\"$A\",\"fp\":$(fp && echo 1 || echo 0),\"mode\":\"${M:--}\",\"dis\":$([ -f $MODROOT/disable ] && echo 1 || echo 0),\"bst\":\"$(cat $BST 2>/dev/null)\",\"rt\":\"$(cat $RTYPE 2>/dev/null)\"}";;
set) [ "$2" = 1 ] && echo 1 > $CONF || echo 0 > $CONF
  # 立刻映射到 FreePPS 的 free 文件（FreePPS 用 inotify 马上处理：1=写 pd_verifed 1；0=未充电写 0、充电中不动）
  mkdir -p $F; w=0; [ "$2" = 1 ] && [ ! -f $MODROOT/disable ] && w=1
  [ "$(cat $F/free 2>/dev/null)" = "$w" ] || { printf "$w" > $F/free; log "开关$([ "$2" = 1 ] && echo 打开 || echo 关闭)：free=$w"; }
  running || { nohup sh ${0%/*}/daemon.sh >/dev/null 2>&1 & sleep 1.5; }
  fp && log "已安装 FreePPS 模块，内置 FreePPS 让出"
  sleep 0.3; sh ${0%/*}/../dtbo/apply.sh desc >/dev/null 2>&1; sh $0 status;;
gold) sh $0 status;; # 金标动画由 FreePPS 内置（公版头自动），旧版开关保留为空操作
plug) S=$(cat $SVID 2>/dev/null); A=$(cat $APDO 2>/dev/null); V=$(cat $(node) 2>/dev/null)
  R=$(cat $RTYPE 2>/dev/null); X=$(cat $PMAX 2>/dev/null)
  log "插入$(head_name "$S")：svid=${S:-?} real_type=${R:-?} apdo_max=${A:-?}W power_max=${X:-?}W，插入瞬间 pd_verifed=${2:-?}，3 秒后 ${V:-?}"
  [ "$V" = 1 ] && [ -n "$A" ] && [ "$A" != 0 ] && echo $A > $D/pps_last;;
unplug) sh ${0%/*}/../dtbo/apply.sh desc >/dev/null 2>&1;;
burst) # 仅 shell 兜底用：与 FreePPS broadcast_forger 相同的金标动画广播（公版头 + PD_PPS + pd=1 + VBUS≥12V）
  t=0; while [ $t -lt 20 ]; do
    [ "$(cat $(node) 2>/dev/null)" = 1 ] && [ "$(cat $SVID 2>/dev/null)" = 0000 ] && [ "$(cat $RTYPE 2>/dev/null)" = PD_PPS ] && [ "$(cat $USB/voltage_now 2>/dev/null || echo 0)" -ge 12000000 ] && break
    sleep 0.1; t=$((t+1)); done
  [ $t -ge 20 ] && exit 0
  A=$(cat $APDO 2>/dev/null); case "$A" in ''|*[!0-9]*) P=100;; *) [ $A -ge 90 ] && P=100 || P=$A;; esac
  b(){ /system/bin/am broadcast -p com.android.systemui -a miui.intent.action.ACTION_QUICK_CHARGE_TYPE --ei miui.intent.extra.quick_charge_type $1 --ei miui.intent.extra.POWER_MAX $P --ei miui.intent.extra.CAR_CHARGE 0 >/dev/null 2>&1; }
  b 1; sleep 0.1
  /system/bin/am broadcast -p com.android.systemui -a miui.intent.action.ACTION_SOC_DECIMAL --ei miui.intent.extra.soc_decimal 0 --ei miui.intent.extra.soc_decimal_rate 0 >/dev/null 2>&1; sleep 0.1
  b 4; sleep 0.25; b 4; sleep 0.4; b 4; log "金标动画 ${P}W（shell）";;
log) # 本模块记录 + FreePPS 自己的日志（logcat 抓取），按时间合并
  { tail -n 40 $LOG 2>/dev/null
    for f in $D/freepps.log.1 $D/freepps.log; do [ -f $f ] && tail -n 60 $f; done | sed -n 's/^\([0-9][0-9]-[0-9][0-9] [0-9:]*\)\.[0-9]* [VDIWE]\/FreePPS *( *[0-9]*): /\1 [FreePPS] /p'
  } | sort -s -k1,2 | tail -n 40
  [ -s $LOG ] || [ -s $D/freepps.log ] || echo 暂无;;
*) echo "用法: pps.sh status|set 0|1|log";;
esac
