HD=/data/adb/mi_charge_boost
CONF=$HD/hz.conf
OFFF=$HD/hz.off     # 存在 = 高刷切换功能关闭，不锁档、不守护
LOCK=/dev/mi_charge_boost_hz.lock
OC="120 132 144 156 165"        # 超频档只能相邻逐级切换
STEP_DELAY=${STEP_DELAY:-1}
LOGF=$HD/hz_switch.log
FAILF=/dev/mi_charge_boost_hz.fail
HISTF=$HD/hz.history   # 切换日志（重启保留，最多 100 条）
STATF=/dev/mi_charge_boost_hz.stat
AVAILF=/dev/mi_charge_boost_hz.avail   # 有 165Hz 模式=1   # 守护进程写入的状态缓存，WebUI 只读这个文件
sf(){ dumpsys SurfaceFlinger 2>/dev/null; }
get_id(){ sf | grep -o "{id=[0-9]*, hwcId=[0-9]*, resolution=[0-9x]*, vsyncRate=$1.00 Hz" | head -n1 | sed 's/{id=\([0-9]*\),.*/\1/'; }
raw_hz(){ sf | grep -m1 -o "activeMode={id=[0-9]*, hwcId=[0-9]*, resolution=[0-9x]*, vsyncRate=[0-9]*" | sed 's/.*vsyncRate=//'; }
# 小米 DDIC 空闲模式（120@idle, ddic_mode=1）：静止画面时面板自动进入，有画面变化立即回到目标档。
# 这时以内核 dsi_display_set_mode 最近一次 ddic_mode=normal 的 fps 为准。
is_idle(){ sf | grep -m1 "activeMode=" | grep -q "ddic_mode=1"; }
kern_hz(){ dmesg 2>/dev/null | grep -o "fps=[0-9]*,ddic_mode=normal" | tail -n1 | sed 's/fps=\([0-9]*\),.*/\1/'; }
kern_n(){ dmesg 2>/dev/null | grep -c "ddic_mode=normal"; }
pol_hz(){ sf | grep -m1 -o "displayManagerPolicy={defaultModeId=[0-9]*" | sed 's/.*=//'; }
cur_hz(){
  if is_idle; then L=$(kern_hz); [ -n "$L" ] && { echo $L; return; }; fi
  raw_hz
}
res(){ sf | grep -o "{id=[0-9]*, hwcId=[0-9]*, resolution=[0-9x]*, vsyncRate=$1.00 Hz" | head -n1 | sed 's/.*resolution=\([0-9x]*\),.*/\1/'; }
lock_mode(){  # 同“屏幕刷新率”App：SF 后门 + 刷新率设置同时锁定
  service call SurfaceFlinger 1035 i32 $2 >/dev/null 2>&1
  settings put system peak_refresh_rate $1.0
  settings put system min_refresh_rate $1.0
  settings put system user_refresh_rate $1
  settings put secure miui_refresh_rate $1
}
commit(){  # 到位后：设为系统“用户首选显示模式”，防止被空闲/系统调度打回
  R=$(res $1); W=${R%x*}; H=${R#*x}
  [ -n "$W" ] && cmd display set-user-preferred-display-mode $W $H $1 >/dev/null 2>&1
  lock_mode $1 $(get_id $1)
}
force(){  # 用 SurfaceFlinger 后门锁定某档，失败重试
  ID=$(get_id $1); [ -z "$ID" ] && { echo "  无 ${1}Hz 模式"; return 1; }
  for n in 1 2 3; do
    K0=$(kern_n)
    lock_mode $1 $ID; sleep $STEP_DELAY
    R=$(cur_hz)
    # 面板处于空闲且内核没有新的切换记录：切换被推迟到下一帧，SF 策略已是目标档即视为到位
    if [ "$R" != "$1" ] && is_idle && [ "$(kern_n)" = "$K0" ] && [ "$(pol_hz)" = "$ID" ]; then R=$1; fi
    echo "  -> ${1}Hz(id=$ID) 第${n}次，实际 ${R}Hz"
    [ "$R" = "$1" ] && return 0
    { echo "$(date '+%H:%M:%S') want $1 id=$ID got $R"; dmesg 2>/dev/null | grep -iE "dsi_display_set_mode|early_trigger" | tail -n 4; } >> $LOGF
  done
  return 1
}
release(){  # 解除后门锁定，交还系统调度
  cmd display clear-user-preferred-display-mode >/dev/null 2>&1
  service call SurfaceFlinger 1035 i32 -1 >/dev/null 2>&1
  settings put system peak_refresh_rate 120.0
  settings delete system min_refresh_rate >/dev/null 2>&1
  settings delete system user_refresh_rate >/dev/null 2>&1
  settings delete secure miui_refresh_rate >/dev/null 2>&1
  sleep $STEP_DELAY
  echo "  已解除锁定，交还系统调度，当前 $(cur_hz)Hz"
}
[ -f $LOGF ] && [ $(wc -c < $LOGF) -gt 200000 ] && { tail -n 300 $LOGF > $LOGF.tmp; mv -f $LOGF.tmp $LOGF; }
diag(){  # 掉档诊断写入 switch.log
  { echo "=== $(date '+%m-%d %H:%M:%S') 诊断 目标$1 ==="
    getprop | grep -iE "idle|fps|refresh|frame_rate|vrr" | head -n 30
    sf | grep -v "GL_" | grep -iE "activeMode|KernelIdleTimer|touchTimer|idleTimer|displayManagerPolicy" | head -n 8
    dmesg 2>/dev/null | grep -iE "early_trigger|thermal.*fps|fps.*limit" | tail -n 8
  } >> $LOGF 2>/dev/null
}
ladder(){  # 从 $1 到 $2 依次输出经过的档位（不含起点）
  echo "$OC" | tr ' ' '\n' | awk -v a=$1 -v b=$2 '{v[NR]=$1} END{
    if(a<b){for(i=1;i<=NR;i++) if(v[i]>a && v[i]<=b) print v[i]}
    else   {for(i=NR;i>=1;i--) if(v[i]<a && v[i]>=b) print v[i]}}'
}
apply_hz(){
  T=$1
  mkdir $LOCK 2>/dev/null || { echo "正在切换中，稍后再试"; return 1; }
  S0=$(date +%s); F0=$(cur_hz)
  echo "目标 ${T}Hz，当前 ${F0}Hz"
  tries=0
  while [ $tries -lt 4 ]; do
    C=$(cur_hz); [ -z "$C" ] && C=120
    [ "$C" = "$T" ] && break
    [ "$T" -le 120 ] && [ "$C" -le 120 ] && break
    if [ "$C" -lt 120 ] || ! echo " $OC " | grep -q " $C "; then force 120; C=$(cur_hz); fi
    NEXT=$(ladder $C $T | head -n1); [ -z "$NEXT" ] && break
    if ! force $NEXT; then
      tries=$((tries+1)); echo "  掉档到 $(cur_hz)Hz，从当前档重新爬升（第${tries}轮）"
    fi
  done
  [ "$T" -gt 120 ] && [ "$(cur_hz)" = "$T" ] && { commit $T; sleep 1; }
  [ "$T" -le 120 ] && release
  N=$(cur_hz)
  if [ "$T" -le 120 ] || [ "$N" = "$T" ]; then echo "完成：当前 ${N}Hz"; rm -f $FAILF
  else echo "未到位：当前 ${N}Hz，诊断已写入 switch.log"; echo $T > $FAILF; diag $T; fi
  if [ "$T" -le 120 ] || [ "$N" = "$T" ]; then RS=成功; else RS=未到位; fi
  hist "${F0:-?}→${T}Hz $RS 实际${N}Hz 用时$(( $(date +%s) - S0 ))s"
  rmdir $LOCK
}

write_stat(){  # 只调用一次 dumpsys，结果缓存给 WebUI
  D=$(timeout 4 dumpsys SurfaceFlinger 2>/dev/null | grep -m1 "activeMode=")
  W=$(echo "$D" | grep -o "vsyncRate=[0-9]*" | head -n1 | sed 's/.*=//'); [ -z "$W" ] && W=0
  I=0; C=$W
  if echo "$D" | grep -q "ddic_mode=1"; then I=1; K=$(kern_hz); [ -n "$K" ] && C=$K; fi
  echo "$C $W $I" > $STATF.tmp && mv -f $STATF.tmp $STATF
}

hist(){  # 写一条切换日志：时间 来源 内容
  echo "$(date '+%m-%d %H:%M:%S') [${SRC:-手动}] $1" >> $HISTF
  [ $(wc -l < $HISTF) -gt 120 ] && { tail -n 100 $HISTF > $HISTF.tmp; mv -f $HISTF.tmp $HISTF; }
}
