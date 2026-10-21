#!/system/bin/sh
# 每秒调用：只用 shell 内建 read，避免频繁 fork
MODDIR=${0%/*}
D=/data/adb/mi_charge_boost
[ -f $D/ps.cache ] || sh $MODDIR/detect.sh >/dev/null 2>&1
. $D/ps.cache
[ "$CV" = 60 ] || { sh $MODDIR/detect.sh >/dev/null 2>&1; . $D/ps.cache; }
rd(){ [ -r "$2" ] && { IFS= read -r v < "$2"; echo "$1=$v"; }; }
rd cap $BAT/capacity; rd status $BAT/status; if [ -f $D/soft_on ] && [ -f $D/real_temp ]; then rd temp $D/real_temp; else rd temp $BAT/temp; fi
rd volt $BAT/voltage_now
if [ -r $BAT/current_now ]; then rd curr $BAT/current_now; else rd curr /sys/class/power_supply/bms/current_now; fi
rd cycle $BAT/cycle_count; rd cycr /sys/class/xm_power/fg_master/qmax_cyclecount; rd health $BAT/health
rd full $BAT/charge_full; rd design $BAT/charge_full_design
on=0; for f in $ONL; do [ -r $f ] && { IFS= read -r v < $f; [ "$v" = "1" ] && on=1; }; done
echo "online=$on"
if [ -n "$USB" ]; then rd usb_v $USB/voltage_now; if [ -r $USB/input_current_now ]; then rd usb_i $USB/input_current_now; elif [ -n "$IBT" ] && [ -r "$IBT" ]; then read -r v < "$IBT"; case "$v" in ''|*[!0-9-]*) ;; *) echo "usb_i=$((v*1000))";; esac; fi; fi
[ -n "$UT" ] && rd usb_type $UT
# 双电芯：每节电压/电流/QMAX（节点不存在时不输出）
rd c1v "$C1V"; rd c2v "$C2V"; rd c1i "$C1I"; rd c2i "$C2I"; rd c1q "$C1Q"; rd c2q "$C2Q"; rd pmax "$PMX"
[ -n "$FGL" ] && echo "fgl=$FGL"
if [ -f $D/detail.list ]; then
  while IFS='|' read -r lab path; do [ -r "$path" ] && { IFS= read -r v < "$path"; case "$path" in *charge_counter) case "$v" in *[!0-9-]*|"") ;; *) v=$((v/1000));; esac;; esac; echo "dt|$lab=$v"; }; done < $D/detail.list
fi
for e in $TZ; do n=${e%%:*}; f=${e#*:}; [ -r $f ] && { IFS= read -r v < $f; echo "tz|$n=$v"; }; done
[ -f $D/current ] && { IFS= read -r v < $D/current; echo "rec=$v"; }
if [ -f $D/logger.pid ]; then IFS= read -r p < $D/logger.pid; kill -0 $p 2>/dev/null && echo "logger=1"; fi
if [ -f $D/lowbat.pid ]; then IFS= read -r p < $D/lowbat.pid; kill -0 $p 2>/dev/null && echo "lowbat=1"; fi
[ -f $D/shutdown_mv ] && { IFS= read -r v < $D/shutdown_mv; echo "smv=$v"; }
true
