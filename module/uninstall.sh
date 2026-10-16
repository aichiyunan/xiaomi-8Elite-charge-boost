#!/system/bin/sh
# 卸载时把本模块写入的 dtbo 还原为原版
X=/data/adb/mi_charge_boost/dtbo; S=$(getprop ro.boot.slot_suffix)
if [ "$(cat $X/state$S 2>/dev/null)" = mod ] && [ -f $X/stock.img ]; then
  B=/dev/block/by-name/dtbo$S; [ -e $B ] && { blockdev --setrw $B 2>/dev/null; dd if=$X/stock.img of=$B bs=1048576 conv=fsync 2>/dev/null; sync; }
fi
# 高刷切换：解除锁定交还系统（只有小米15 用过高刷切换；其它机型不动刷新率设置）
if [ "$(cat ${0%/*}/model 2>/dev/null || echo dada)" = dada ]; then
cmd display clear-user-preferred-display-mode >/dev/null 2>&1
service call SurfaceFlinger 1035 i32 -1 >/dev/null 2>&1
settings put system peak_refresh_rate 120.0
settings delete system min_refresh_rate >/dev/null 2>&1
settings delete system user_refresh_rate >/dev/null 2>&1
settings delete secure miui_refresh_rate >/dev/null 2>&1
fi
# 软断充温度：撤销伪装、恢复充电
for n in /sys/class/xm_power/fuelgauge/strategy_fg/fake_temp; do [ -f $n ] && echo -999 > $n; done
[ -f /data/adb/mi_charge_boost/soft_stop ] && echo 0 > /sys/class/xm_power/charger/charge_interface/input_suspend 2>/dev/null
[ -f /data/adb/mi_charge_boost/cc_stop ] && echo 0 > /sys/class/xm_power/charger/charge_interface/input_suspend 2>/dev/null
# 实时充电电流：写回最大值交还系统温控
N=/sys/class/xm_power/charger/charger_thermal/wired_chg_curr; [ -f $N ] && echo 22000000 > $N 2>/dev/null
# 低电量延迟关机：还原小米 30 秒关机倒计时开关
[ -f /data/adb/mi_charge_boost/sde.list ] && while IFS='|' read -r f v; do [ -f "$f" ] && [ -n "$v" ] && echo "$v" > "$f" 2>/dev/null; done < /data/adb/mi_charge_boost/sde.list
rm -rf /data/adb/mi_charge_boost
