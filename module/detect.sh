#!/system/bin/sh
# 扫描电池详情节点，写入 detail.list（标签|路径）
MODDIR=${0%/*}
. $MODDIR/common.sh
find_ps
out=$D/detail.list; : > $out
dirs="$BAT /sys/class/power_supply/battery /sys/class/power_supply/bms /sys/class/qcom-battery /sys/class/xm_power /sys/class/power_supply/batt_verify /sys/class/power_supply/fuelgauge"
add(){ # 标签 文件名候选...
  lab=$1; shift
  for d in $dirs; do [ -d "$d" ] || continue
    for n in "$@"; do
      if [ -f "$d/$n" ] && v=$(cat "$d/$n" 2>/dev/null) && [ -n "$v" ]; then echo "$lab|$d/$n" >> $out; return; fi
    done
  done
}
add "电池寿命(SOH)" soh battery_soh state_of_health
add "QMAX" qmax qmax0 batt_qmax fg_qmax
add "剩余容量(RM)" rm remaining_capacity fg_rm charge_counter
add "电芯电压" cell_voltage cell1_voltage cell1_volt batt_cell1_vol vcell fg_vcell
add "电池型号" battery_type model_name batt_type battery_id_name
add "电池厂商" manufacturer battery_vendor batt_manufacturer
add "生产日期" manufacturing_date battery_date mfg_date manufacture_date
add "温控等级" system_temp_level thermal_level
add "充电电流上限" constant_charge_current_max fcc
add "预计充满" time_to_full_now
# 充电协议（以 P: 开头的标签显示在“充电协议”区）
pf(){ [ -f "$2" ] && v=$(cat "$2" 2>/dev/null) && [ -n "$v" ] && echo "P:$1|$2" >> $out; }
Q=/sys/class/qcom-battery; T=/sys/class/typec/port0; PT=/sys/class/power_supply/typec
pf "快充类型" $Q/quick_charge_type
pf "实际充电器类型" $Q/real_type
pf "USB 实际类型" $Q/usb_real_type
pf "小米适配认证" $Q/pd_verified
pf "系统标称功率" $Q/power_max
pf "Type-C 供电模式" $T/power_operation_mode
pf "Type-C 供电角色" $T/power_role
pf "USB PD 版本" $T/usb_power_delivery_revision
pf "APDO 最大功率" $PT/apdo_max
pf "PPS PTF" $PT/typec_pps_ptf
# xm_power 下按文件名模糊查找
for kw in fast_charge apdo adapter_id strategy charger_type pd_auth; do
  f=$(find -L /sys/class/xm_power -maxdepth 4 -name "*$kw*" -type f 2>/dev/null | head -n 2)
  for x in $f; do pf "xm ${x##*/}" "$x"; done
done
# 缓存节点路径，read.sh 每秒读取时不再遍历
{
  echo "CV=60"; echo "BAT='$BAT'"; echo "USB='$USB'"
  ps=""; for p in /sys/class/power_supply/*; do
    [ -f $p/online ] || continue
    case "$(cat $p/type 2>/dev/null)" in Battery|BMS|Unknown) ;; *) ps="$ps $p/online";; esac
  done; echo "ONL='$ps'"
  tz=""; n=0; for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat $z/type 2>/dev/null)
    case "$t" in *usb*|*conn*|*chg*|*charger*|*batt*|*skin*) [ $n -lt 8 ] && { tz="$tz $t:$z/temp"; n=$((n+1)); };; esac
  done; echo "TZ='$tz'"
  UT=""; [ -n "$USB" ] && { [ -f $USB/real_type ] && UT=$USB/real_type || UT=$USB/usb_type; }
  [ -f /sys/class/qcom-battery/usb_real_type ] && UT=/sys/class/qcom-battery/usb_real_type
  echo "UT='$UT'"
  # 双电芯（小米 xm_power 主/副电量计）：按候选文件名找每节的电压、电流、QMAX
  fgf(){ for n in $2; do [ -f "$1/$n" ] && cat "$1/$n" >/dev/null 2>&1 && { echo "$1/$n"; return; }; done; }
  FM=/sys/class/xm_power/fg_master; FS=/sys/class/xm_power/fg_slave
  VN="voltage_now vbat fg_vbat batt_vol vol voltage vcell cell_voltage"
  IN="current_now ibat fg_ibat batt_curr curr current"
  QN="qmax fg_qmax qmax0 batt_qmax"
  QB=/sys/class/qcom-battery
  if [ -f $QB/fg1_voltage ] && [ -f $QB/fg2_voltage ]; then
    # 小米平板 8 Pro 等：qcom-battery 下 fg1_/fg2_ 两个电量计（电压 µV，电流 mA）
    echo "C1V=$QB/fg1_voltage"; echo "C2V=$QB/fg2_voltage"
    [ -f $QB/fg1_current ] && echo "C1I=$QB/fg1_current"; [ -f $QB/fg2_current ] && echo "C2I=$QB/fg2_current"
    [ -f $QB/fg1_qmax ] && echo "C1Q=$QB/fg1_qmax"; [ -f $QB/fg2_qmax ] && echo "C2Q=$QB/fg2_qmax"
  elif [ -d $FM ] && [ -d $FS ]; then
    echo "C1V='$(fgf $FM "$VN")'"; echo "C2V='$(fgf $FS "$VN")'"
    echo "C1I='$(fgf $FM "$IN")'"; echo "C2I='$(fgf $FS "$IN")'"
    echo "C1Q='$(fgf $FM "$QN")'"; echo "C2Q='$(fgf $FS "$QN")'"
    echo "FGL='$(ls $FM 2>/dev/null | tr '\n' ' ')'"
  fi
  [ -f /sys/class/qcom-battery/power_max ] && echo "PMX=/sys/class/qcom-battery/power_max"
  [ -f /sys/class/qcom-battery/ibus_total ] && echo "IBT=/sys/class/qcom-battery/ibus_total"
} > $D/ps.cache
cat $out
