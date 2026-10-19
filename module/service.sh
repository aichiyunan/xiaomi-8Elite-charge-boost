#!/system/bin/sh
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
D0=/data/adb/mi_charge_boost; if [ -f $D0/cm_pending ] && [ -f $D0/apk/charge_monitor.apk ]; then sleep 20; cp $D0/apk/charge_monitor.apk /data/local/tmp/cm.apk; chmod 644 /data/local/tmp/cm.apk; r=$(pm install -r -g /data/local/tmp/cm.apk 2>&1); case "$r" in *UPDATE_INCOMPATIBLE*|*SIGNATURES*) pm uninstall com.yunan.chargehub >/dev/null 2>&1; r=$(pm install -r -g /data/local/tmp/cm.apk 2>&1);; esac; case "$r" in *Success*) rm -rf $D0/cm_pending $D0/apk;; esac; rm -f /data/local/tmp/cm.apk; fi
D=/data/adb/mi_charge_boost; mkdir -p $D/sessions
rm -f $D/current $D/logger.pid $D/lowbat.pid $D/pps.pid $D/pps.mode $D/pps.phase $D/pps_head $D/freepps.pid
nohup sh $MODDIR/logger.sh >/dev/null 2>&1 &
nohup sh $MODDIR/lowbat.sh >/dev/null 2>&1 &
# dtbo 被系统更新或手动刷回时提醒
(sleep 20; sh $MODDIR/dtbo/apply.sh desc >/dev/null 2>&1; st=$(sh $MODDIR/dtbo/apply.sh status 2>/dev/null)
case "$st" in changed*)
  cmd notification post -S bigtext -t "$(sed -n 's/^name=//p' $MODDIR/module.prop)" dtbo_charge "检测到 dtbo 已还原（系统更新或手动刷回），之前的充电电流/关机电压设置已失效。请打开充电监控 WebUI 重新应用。" >/dev/null 2>&1;;
esac) &
# 高刷切换守护
nohup sh $MODDIR/hz/daemon.sh >/dev/null 2>&1 &
# 免重启解除温控守护
nohup sh $MODDIR/tr/daemon.sh >/dev/null 2>&1 &
# 软断充温度已移除：清理旧配置，若上次停在停充状态则恢复
[ -f $D/soft_stop ] && echo 0 > /sys/class/xm_power/charger/charge_interface/input_suspend 2>/dev/null
rm -f $D/soft $D/soft_on $D/soft_stop $D/soft_src $D/soft_unit $D/soft_fakeok $D/real_temp
# 公版 PPS 解锁：内置 FreePPS v1.7.0（Seyud，GPL-3.0），daemon.sh 负责开关映射/让出/日志，跑不起来时 shell 兜底
chmod 0755 $MODDIR/pps/FreePPS 2>/dev/null
nohup sh $MODDIR/pps/daemon.sh >/dev/null 2>&1 &
nohup sh $MODDIR/hs/daemon.sh >/dev/null 2>&1 &
# 快充断流秒恢复（mi_qc_retry.ko，开关默认关闭；开机 60 秒后按配置加载）
(sleep 60; sh $MODDIR/qr/qr.sh boot) &
# 实时充电电流守护
nohup sh $MODDIR/cc/daemon.sh >/dev/null 2>&1 &
