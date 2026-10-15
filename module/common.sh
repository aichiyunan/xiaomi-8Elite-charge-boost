# 公共函数：定位电池与充电节点
D=/data/adb/mi_charge_boost
mkdir -p $D/sessions 2>/dev/null
find_ps(){
  BAT=""; USB=""
  [ -f /sys/class/power_supply/battery/capacity ] && BAT=/sys/class/power_supply/battery
  for p in /sys/class/power_supply/*; do
    t=$(cat $p/type 2>/dev/null)
    [ -z "$BAT" ] && [ "$t" = "Battery" ] && [ -f $p/capacity ] && BAT=$p
  done
  [ -f /sys/class/power_supply/usb/online ] && USB=/sys/class/power_supply/usb
  if [ -z "$USB" ]; then
    for p in /sys/class/power_supply/*; do
      case "$(cat $p/type 2>/dev/null)" in USB*) USB=$p; break;; esac
    done
  fi
}
