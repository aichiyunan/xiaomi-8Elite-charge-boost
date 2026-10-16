#!/system/bin/sh
# 公版 PPS 解锁守护（v8.5.3）：PPS 逻辑完全由内置的 FreePPS v1.7.0 执行
#   FreePPS 作者 Seyud（酷安@瓦力喀），GPL-3.0，https://github.com/Seyud/FreePPS
#   本模块只改了它的路径常量（见 freepps-paths.patch），逻辑与原版一致。
# 本脚本不写任何 PPS 节点，只负责：
#   1. 跟 FreePPS 的 service.sh 一样，等开机完成且用户解锁后再启动 FreePPS
#   2. 把 WebUI「公版 PPS 解锁」开关（$D/pps）映射为 FreePPS 的 free 文件 1/0；本模块被禁用时映射为 0
#   3. 已安装并启用 FreePPS 模块时停掉内置 FreePPS（让出），停用/卸载后恢复
#   4. 插入/拔出时只读记录充电头信息到 pps.log；FreePPS 自己的日志用 logcat 存到 freepps.log
#   5. 内置 FreePPS 无法运行时才改用 shell 兜底（轮询 battery/status，按 FreePPS 同样的规则写）
MODDIR=${0%/*}; P=$MODDIR/pps.sh; D=${PPS_DATA:-/data/adb/mi_charge_boost}; S0=${PPS_SYS:-}
MODROOT=${MODDIR%/pps}; F=$D/freepps
BIN=${PPS_BIN:-$MODDIR/FreePPS}; MODS=${PPS_MODS:-/data/adb/modules}
LOG=$D/pps.log
lg(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 300 ] && sed -i '1,150d' $LOG; }

# 同 FreePPS service.sh 的 wait_until_login
wait_until_login() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
    done
    local test_file="/sdcard/Android/.PERMISSION_TEST"
    true >"$test_file"
    while [ ! -f "$test_file" ]; do
        true >"$test_file"
        sleep 1
    done
    rm "$test_file"
}
[ -n "$PPS_TEST" ] || wait_until_login

mkdir -p $D $F
if [ -f $D/pps.pid ] && kill -0 $(cat $D/pps.pid) 2>/dev/null && [ "$(cat $D/pps.pid)" != $$ ]; then exit 0; fi
echo $$ > $D/pps.pid
# FreePPS 会在自己的 module.prop 描述前加状态前缀，这里给它一个占位文件，不碰本模块的 module.prop
[ -f $F/module.prop ] || printf 'id=FreePPS\nname=FreePPS（内置于 mi_charge_boost）\nversion=v1.7.0\ndescription=占位文件，内置 FreePPS 在这里写状态，不影响本模块描述\n' > $F/module.prop

fp(){ [ -d $MODS/FreePPS ] && [ ! -f $MODS/FreePPS/disable ] && [ ! -f $MODS/FreePPS/remove ]; }
rd(){ v=; [ -f $1 ] && read -r v < $1 2>/dev/null; }
want(){ w=0; rd $D/pps; [ "$v" = 1 ] && [ ! -f $MODROOT/disable ] && w=1; }
# 开关 → free（只在值变化时写，跟 FreePPS action.sh 一样用 printf 写 1/0）
sync_free(){ want; rd $F/free; [ "$v" = "$w" ] || { printf "$w" > $F/free; lg "开关映射：free=$w（$([ $w = 1 ] && echo 开启 || { [ -f $MODROOT/disable ] && echo 模块已禁用 || echo 关闭; })）"; }; }
alive(){ [ -n "$1" ] && kill -0 $1 2>/dev/null && grep -q FreePPS /proc/$1/cmdline 2>/dev/null; }
LPID=
start_bin(){
  [ -f $BIN ] || return 1
  chmod 0755 $BIN 2>/dev/null
  nohup $BIN >/dev/null 2>&1 &
  BPID=$!; sleep 1
  alive $BPID || { BPID=; return 1; }
  echo $BPID > $D/freepps.pid
  echo "FreePPS 1.7.0 uevent $BPID" > $D/pps.mode
  # 同 FreePPS 的 debug 模式：用 logcat 抓它自己的日志（限 128KB×2 个文件）
  if [ -z "$PPS_TEST" ] && command -v logcat >/dev/null 2>&1; then
    [ -n "$LPID" ] && kill $LPID 2>/dev/null
    nohup nice -n 10 logcat -b main --pid=$BPID -s FreePPS:V -v time -f $D/freepps.log -r 128 -n 1 >/dev/null 2>&1 &
    LPID=$!
  fi
  return 0
}
stop_bin(){ alive $BPID && { kill $BPID 2>/dev/null; n=0; while alive $BPID && [ $n -lt 20 ]; do sleep 0.1; n=$((n+1)); done; alive $BPID && kill -9 $BPID 2>/dev/null; }
  [ -n "$LPID" ] && kill $LPID 2>/dev/null; LPID=; BPID=; rm -f $D/freepps.pid; }

ONP=$S0/sys/class/power_supply/usb/online
PVN=$S0/sys/class/qcom-battery/pd_verifed; [ -f $PVN ] || PVN=$S0/sys/class/Charging_Adapter/pd_adapter/usbpd_verifed
# 插拔只读记录（不写任何节点）
plugwatch(){
  rd $ONP; on=${v:-0}
  if [ "$on" = 1 ] && [ "$last" != 1 ]; then rd $PVN; (sleep 3; sh $P plug "$v") &
  elif [ "$on" != 1 ] && [ "$last" = 1 ]; then rd $PVN; p0=$v; (sleep 2; rd $PVN; lg "拔出：拔出瞬间 pd_verifed=${p0:-?}，2 秒后 ${v:-?}（$(cut -d" " -f1 $D/pps.mode 2>/dev/null) 处理）"; sh $P unplug) &
  fi
  last=$on
}

# ---------- shell 兜底（只在内置 FreePPS 无法运行时使用；规则同 FreePPS 高通/MTK 路径，但没有 uevent，改为 0.5 秒读 battery/status） ----------
shell_engine(){
  echo $$ > $D/pps.pid; echo "shell poll" > $D/pps.mode
  QC=$S0/sys/class/qcom-battery/pd_verifed; MT=$S0/sys/class/Charging_Adapter/pd_adapter/usbpd_verifed; BS=$S0/sys/class/power_supply/battery/status
  wpd(){ [ -f $1 ] && echo $2 > $1 2>/dev/null; }
  f0=-; sess=0; y=0
  while true; do
    if fp; then [ $y = 1 ] || lg "已启用 FreePPS 模块，本模块 PPS 让出"; y=1; f0=-; sleep 3; continue; fi; y=0
    sync_free; rd $F/free; fr=$v; rd $BS; bs=$v
    if [ "$fr" != "$f0" ]; then
      if [ "$fr" = 1 ]; then wpd $QC 1; wpd $MT 1; lg "shell：free=1，pd_verifed 写 1"; [ "$bs" = Charging ] && { sess=1; sh $P burst & }
      else if [ "$bs" = Discharging ]; then wpd $QC 0; wpd $MT 0; lg "shell：free=0，未充电，pd_verifed 写 0"; else lg "shell：free=0，充电中不动 pd_verifed"; fi; sess=0; fi
      f0=$fr
    fi
    if [ "$fr" = 1 ]; then
      if [ "$bs" = Charging ] && [ $sess = 0 ]; then sess=1; sh $P burst &
      elif [ "$bs" = Discharging ] && [ $sess = 1 ]; then sess=0; rd $QC; [ "$v" = 0 ] && wpd $QC 1 && lg "shell：Charging→Discharging，pd_verifed=0，写回 1"; fi
      rd $MT; [ "$v" = 0 ] && wpd $MT 1
    fi
    plugwatch; sleep 0.5
  done
}

rd $ONP; last=${v:-0}
sync_free
BPID=; rd $D/freepps.pid; alive "$v" && BPID=$v && lg "接管已在运行的内置 FreePPS（pid $BPID）"
crash=0; yielded=0; t0=
while true; do
  if fp; then
    if [ $yielded = 0 ]; then stop_bin; t0=; echo "yield FreePPS" > $D/pps.mode; lg "已启用 FreePPS 模块，内置 FreePPS 停止（让出）"; yielded=1; fi
    sleep 3; continue
  fi
  sync_free
  if ! alive "$BPID"; then
    [ -n "$t0" ] && crash=$((crash+1)) && lg "内置 FreePPS 已退出（第 $crash 次）"
    if [ $yielded = 1 ]; then lg "FreePPS 模块已停用/卸载，恢复内置 FreePPS"; yielded=0; fi
    up=$(cut -d. -f1 /proc/uptime)
    # 运行超过 60 秒才退出的不算连续失败
    [ -n "$t0" ] && [ $((up - t0)) -gt 60 ] && crash=0
    if start_bin; then
      t0=$up; lg "内置 FreePPS v1.7.0 启动（pid $BPID，free=$w）"
    else
      t0=; crash=$((crash+1))
      if [ $crash -ge 3 ]; then lg "内置 FreePPS 无法运行（连续 $crash 次），改用 shell 兜底"; shell_engine; fi
      lg "内置 FreePPS 启动失败/退出（第 $crash 次），5 秒后重试"; sleep 5; continue
    fi
  fi
  plugwatch
  sleep 1
done
