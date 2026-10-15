#!/system/bin/sh
# 后台记录：充电时记录充电日志；拔掉充电器后记录放电日志（含低电量锁 2% / 关机过程）
MODDIR=${0%/*}
. $MODDIR/common.sh
if [ -f $D/logger.pid ] && kill -0 $(cat $D/logger.pid) 2>/dev/null; then exit 0; fi
echo $$ > $D/logger.pid
find_ps
cur=""; last=0; lt=0; dl=0
X=/sys/class/xm_power; mkdir -p $D/logs $D/dlogs
NODES="charger/charger_common/quick_charge_type charger/charger_common/power_max charger/charger_common/real_type charger/charge_interface/charge_enable charger/charge_interface/ichg_limit charger/charge_interface/iin_limit charger/charger_thermal/wired_thermal_remove charger/charger_thermal/wired_chg_curr charger/charger_thermal/wired_ctrl_limit fuelgauge/strategy_fg/fake_temp fuelgauge/strategy_fg/pack_tbat typec/strategy_pd_auth/adapter_svid typec/apdo_max"
# 截止电压 / FFC 状态：自动发现 xm_power 与 battery 下的相关节点（最多 14 个）
XN=$(cd $X 2>/dev/null && find -L . -maxdepth 3 -type f 2>/dev/null | grep -iE "ffc|fastchg|(^|[/_])(fv|cv)([_/]|$)|term|vterm|vbat_max|max_vbat|vfloat|float_volt|voltage_max|step_chg|cv_vol" | grep -vE "uevent|/power/|subsystem|/device/|driver" | sed 's#^\./##' | head -14 | tr '\n' ' ')
NODES="$NODES $XN"
BN=""; for b in voltage_max constant_charge_voltage constant_charge_voltage_max charge_type charge_full_design; do [ -f $BAT/$b ] && BN="$BN $b"; done
dbg(){ # 调试日志：节点只记变化（每分钟一次完整快照）+ 内核充电日志（同函数同内容去重、高频函数限频）
  lg=$D/logs/${cur##*/}; lg=${lg%.csv}.log
  if [ ! -f $lg ]; then
    { echo "== 小米15充电加速 $(grep ^version= $MODDIR/module.prop | cut -d= -f2) $(getprop ro.product.marketname) $(getprop ro.product.vendor.device) $(getprop ro.build.version.incremental)"
      echo "== dtbo $(sh $MODDIR/dtbo/apply.sh status 2>/dev/null)  温控解除=$(cat $D/thermal_remove 2>/dev/null) 软断充=$(cat $D/soft 2>/dev/null)"
      echo "== 截止电压/FFC 节点：${XN:-未发现} | battery:${BN:-无}"
      echo "== 格式：[时间] 电量 电压mV 电流mA 功率W 温度 | 变化的节点（每 60 秒完整一次）；[k] 为内核日志，时间已换算为墙钟，重复内容合并为 (xN)"; } > $lg
    dl=$(cut -d' ' -f1 /proc/uptime); rm -f $D/klast; dn=0; prev=""
  fi
  t=$(date '+%H:%M:%S'); v=$(cat $BAT/voltage_now); i=$(cat $BAT/current_now)
  l=$(awk -v t=$t -v c=$(cat $BAT/capacity) -v v=$v -v i=$i -v tp=$(cat $BAT/temp) -v r="$(cat $D/real_temp 2>/dev/null)" 'BEGIN{if(v>100000){v/=1000;i/=1000} printf "[%s] soc=%d v=%d i=%d p=%.1fW temp=%.1f%s", t,c,v,i,v*(i<0?-i:i)/1e6,tp/10,(r!=""?" real="r/10:"")}')
  snap=""; for n in $NODES; do snap="$snap|${n##*/}=$(cat $X/$n 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"; done
  for b in $BN; do snap="$snap|bat.$b=$(cat $BAT/$b 2>/dev/null)"; done
  sc=$(cat /sys/class/thermal/thermal_message/sconfig 2>/dev/null); [ -n "$sc" ] && snap="$snap|sconfig=$sc"
  dn=$((dn+1)); if [ $dn -ge 12 ] || [ -z "$prev" ]; then dn=0; ch=$(echo "$snap" | sed 's/^|//; s/|/ | /g'); [ -n "$ch" ] && l="$l | $ch"
  else ch=$(printf '%s\n%s\n' "$prev" "$snap" | awk -F'|' 'NR==1{for(k=2;k<=NF;k++)o[k]=$k;next}{s="";for(k=2;k<=NF;k++)if($k!=o[k])s=s" | "$k;print s}'); l="$l$ch"; fi
  prev=$snap
  echo "$l" >> $lg
  up=$(cut -d' ' -f1 /proc/uptime); now=$(date +%s); off=$(date +%z | awk '{g=(substr($0,1,1)=="-")?-1:1; print g*(substr($0,2,2)*3600+substr($0,4,2)*60)}')
  dmesg 2>/dev/null | grep -iE "mca_|thermal|ffc|pd_verif|cp_|quick_charge|jeita|vote|fuelgauge|strategy" | grep -vE "temperature out of range|avc: +denied" | \
  awk -v a=$dl -v up=$up -v now=$now -v off=$off -v st=$D/klast '
    BEGIN{ while((getline x < st)>0){ split(x,q,"\t"); lm[q[1]]=q[2]; lt[q[1]]=q[3] } close(st)
      # 周期性刷屏的函数：内容不变不记，变了也最多每 30 秒一条
      split("mca_battery_shutdown_update_vcutoff_para charge_slowly_monitor_func fg_update_status smart_charge_handle_bypass_chg strategy_buckchg_update_charge_status mca_wireless_charger_thermal_handle_limit",h," "); for(k in h)hf[h[k]]=1 }
    { if(!match($0,/^\[ *[0-9]+\.[0-9]+\]/))next; ts=substr($0,2,RLENGTH-2)+0; if(ts<=a)next
      msg=substr($0,RLENGTH+1); sub(/^ +/,"",msg); sub(/^\[[0-9:\-A-Z]+\]\[ *[0-9]+\]/,"",msg)
      key=msg; if(match(msg,/[a-zA-Z_0-9]+:[0-9]+ /)){key=substr(msg,RSTART,RLENGTH); sub(/:[0-9]+ $/,"",key)} else key=substr(msg,1,24)
      body=msg; gsub(/[0-9]+/,"#",body)
      if(lm[key]==msg){ dup[key]++; next }
      if((key in hf) && ts-lt[key]<30 && lt[key]!=""){ dup[key]++; lm[key]=msg; next }
      e=int(now-(up-ts)+off)%86400; w=sprintf("%02d:%02d:%02d",int(e/3600),int(e%3600/60),e%60); d=(dup[key]>0)?"  (前面同类 x"dup[key]" 已合并)":""; dup[key]=0
      print "[" w "][k] " msg d; lm[key]=msg; lt[key]=ts }
    END{ printf "" > st; for(k in lm) printf "%s\t%s\t%s\n",k,lm[k],lt[k] >> st }' >> $lg
  dl=$up
  # 最多保留 30 次，总大小不超过 60MB
  n=$(ls $D/logs | wc -l); [ $n -gt 30 ] && ls $D/logs | sort -n | head -n $((n-30)) | while read x; do rm -f $D/logs/$x; done
  while [ $(du -sk $D/logs | cut -f1) -gt 61440 ] && [ $(ls $D/logs | wc -l) -gt 1 ]; do rm -f $D/logs/$(ls $D/logs | sort -n | head -1); done
}
summarize(){
  f=$1
  [ -s "$f" ] || { rm -f "$f"; return; }
  n=$(wc -l < "$f")
  if [ "$n" -lt 3 ]; then rm -f "$f"; return; fi
  awk -F, -v name="${f##*/}" '
    { v=$3; i=$4; if(i<0)i=-i; if(v>100000){v/=1e6;i/=1e6}else{v/=1e3;i/=1e3}
      p=v*i; t=$5/10
      if(NR==1){s=$1;c0=$2;mt=t;pk=p}
      if(NR>1){dt=$1-lt; if(dt>0&&dt<120) e+=p*dt/3600}
      if(p>pk)pk=p; if(t>mt)mt=t; sp+=p; lt=$1; c1=$2 }
    END{ printf "%s,%d,%d,%d,%d,%.2f,%.2f,%.1f,%.2f,%d\n", name, s, lt, c0, c1, pk, sp/NR, mt, e, NR }' "$f" >> $D/index.csv
  lg=$D/logs/${f##*/}; lg=${lg%.csv}.log
  [ -f $lg ] && tail -1 $D/index.csv | awk -F, '{m=int(($3-$2)/60); printf "== 充电结束：%d%% → %d%%，用时 %d 分钟，峰值 %.1fW，平均 %.1fW，最高温 %.1f°C，充入 %.2fWh\n",$4,$5,m,$6,$7,$8,$9}' >> $lg
  # 只保留最近 100 次
  cnt=$(ls $D/sessions | wc -l)
  if [ "$cnt" -gt 100 ]; then
    ls $D/sessions | sort -n | head -n $((cnt-100)) | while read x; do rm -f "$D/sessions/$x"; grep -v "^$x," $D/index.csv > $D/index.tmp; mv $D/index.tmp $D/index.csv; done
  fi
}
# ===== 放电日志 =====
dcur=""; dlt=0
# 上次放电日志没正常结束（关机 / 重启 / 进程被杀），补一行结尾
if [ -f $D/dcurrent ]; then of=$D/dlogs/$(cat $D/dcurrent); [ -f "$of" ] && echo "== 日志在 $(date -r "$of" '+%m-%d %H:%M:%S' 2>/dev/null) 中断（关机或重启），开机后结束本次记录" >> "$of"; rm -f $D/dcurrent; fi
sdinfo(){ for f in $BAT/shutdown_delay /sys/class/power_supply/bms/shutdown_delay /sys/class/qcom-battery/shutdown_delay \
  $(find -L /sys/class/xm_power /sys/class/qcom-battery -maxdepth 4 -name "*shutdown_delay*" -type f 2>/dev/null); do
  [ -f "$f" ] && echo "$f=$(cat $f 2>/dev/null)"; done | sort -u | tr '\n' ' '; }
klog(){ # $1 日志文件 $2 起始 uptime $3 状态文件 $4 过滤正则
  up=$(cut -d' ' -f1 /proc/uptime); now2=$(date +%s); off=$(date +%z | awk '{g=(substr($0,1,1)=="-")?-1:1; print g*(substr($0,2,2)*3600+substr($0,4,2)*60)}')
  dmesg 2>/dev/null | grep -iE "$4" | grep -vE "avc: +denied" | \
  awk -v a=$2 -v up=$up -v now=$now2 -v off=$off -v st=$3 '
    BEGIN{ while((getline x < st)>0){ split(x,q,"\t"); lm[q[1]]=q[2]; lt[q[1]]=q[3] } close(st) }
    { if(!match($0,/^\[ *[0-9]+\.[0-9]+\]/))next; ts=substr($0,2,RLENGTH-2)+0; if(ts<=a)next
      msg=substr($0,RLENGTH+1); sub(/^ +/,"",msg); sub(/^\[[0-9:\-A-Z]+\]\[ *[0-9]+\]/,"",msg)
      key=msg; if(match(msg,/[a-zA-Z_0-9]+:[0-9]+ /)){key=substr(msg,RSTART,RLENGTH); sub(/:[0-9]+ $/,"",key)} else key=substr(msg,1,24)
      if(lm[key]==msg){ dup[key]++; next }
      if(ts-lt[key]<60 && lt[key]!=""){ dup[key]++; lm[key]=msg; next }
      e=int(now-(up-ts)+off)%86400; w=sprintf("%02d:%02d:%02d",int(e/3600),int(e%3600/60),e%60); d=(dup[key]>0)?"  (前面同类 x"dup[key]" 已合并)":""; dup[key]=0
      print "[" w "][k] " msg d; lm[key]=msg; lt[key]=ts }
    END{ printf "" > st; for(k in lm) printf "%s\t%s\t%s\n",k,lm[k],lt[k] >> st }' >> $1
  KUP=$up; }
KRE="shutdown|vcutoff|cutoff|low_?bat|batt?_?low|uvlo|soc_(drop|jump)|fg_update_status|power_off|poweroff"
dlog_start(){
  dcur=$now.log; echo $dcur > $D/dcurrent; dlg=$D/dlogs/$dcur
  d0=$(cat $BAT/capacity); dt0=$now; dnn=0; de=0; dpt=0; dpk=0; dsp=0; dmt=0; dlt=0; rm -f $D/dklast; KUP=$(cut -d' ' -f1 /proc/uptime)
  MVs=$(cat $D/shutdown_mv 2>/dev/null); [ -n "$MVs" ] || MVs=2800
  { echo "== 小米15充电加速 $(grep ^version= $MODDIR/module.prop | cut -d= -f2) 放电日志 $(getprop ro.product.marketname) $(getprop ro.product.vendor.device) $(getprop ro.build.version.incremental)"
    echo "== 低电量延迟关机：$([ "$MVs" = 0 ] && echo 已关闭 || echo "开启，关机电压 ${MVs}mV")  | dtbo $(sh $MODDIR/dtbo/apply.sh status 2>/dev/null)"
    echo "== 倒计时节点：$(sdinfo)"; [ -f $D/sde.list ] && echo "== 倒计时开关原值（模块关闭前）：$(tr '\n' ' ' < $D/sde.list)"
    echo "== 格式：[时间] 真实电量 电压mV 电流mA 功率W 温度（>20% 每 60 秒，≤20% 每 30 秒，≤10% 每 10 秒，≤2% 每 5 秒）；[低电量] 为锁 2% / 清倒计时 / 关机事件；[k] 为内核日志"; } > $dlg
}
dlog_line(){
  t=$(date '+%H:%M:%S'); v=$(cat $BAT/voltage_now); i=$(cat $BAT/current_now); c=$(cat $BAT/capacity); tp=$(cat $BAT/temp)
  l=$(awk -v t=$t -v c=$c -v v=$v -v i=$i -v tp=$tp 'BEGIN{if(v>100000){v/=1000;i/=1000} printf "[%s] soc=%d v=%d i=%d p=%.1fW temp=%.1f", t,c,v,i,v*(i<0?-i:i)/1e6,tp/10}')
  [ "${c:-100}" -le 10 ] && l="$l | sd: $(sdinfo)"
  echo "$l" >> $dlg
  p=$(echo "$l" | sed 's/.* p=\([0-9.]*\)W.*/\1/'); dnn=$((dnn+1))
  eval $(awk -v p=$p -v now=$now -v pt=$dpt -v e=$de -v pk=$dpk -v sp=$dsp -v mt=$dmt -v tp=$tp 'BEGIN{dt=now-pt; if(pt>0&&dt>0&&dt<400)e+=p*dt/3600; if(p>pk)pk=p; sp+=p; if(tp/10>mt)mt=tp/10; printf "de=%.3f dpk=%.1f dsp=%.1f dmt=%.1f", e,pk,sp,mt}')
  dpt=$now; dc1=$c
  klog $dlg $KUP $D/dklast "$KRE"
}
dlog_end(){
  [ -n "$dcur" ] || return
  if [ $dnn -lt 2 ]; then rm -f $dlg
  else m=$(( (now-dt0)/60 )); awk -v a=$d0 -v b=${dc1:-$d0} -v m=$m -v e=$de -v pk=$dpk -v sp=$dsp -v n=$dnn -v mt=$dmt -v r="$1" 'BEGIN{printf "== 放电结束（%s）：%d%% → %d%%，用时 %d 分钟，平均 %.2fW，峰值 %.1fW，最高温 %.1f°C，消耗约 %.2fWh\n",r,a,b,m,sp/n,pk,mt,e}' >> $dlg; fi
  dcur=""; rm -f $D/dcurrent
  # 放电日志最多保留 15 次，总大小不超过 20MB
  n=$(ls $D/dlogs | wc -l); [ $n -gt 15 ] && ls $D/dlogs | sort -n | head -n $((n-15)) | while read x; do rm -f $D/dlogs/$x; done
  while [ $(du -sk $D/dlogs | cut -f1) -gt 20480 ] && [ $(ls $D/dlogs | wc -l) -gt 1 ]; do rm -f $D/dlogs/$(ls $D/dlogs | sort -n | head -1); done
}
while true; do
  [ -n "$BAT" ] || { find_ps; sleep 30; continue; }
  st=$(cat $BAT/status 2>/dev/null)
  now=$(date +%s)
  if [ "$st" = "Charging" ]; then
    [ -n "$dcur" ] && dlog_end 开始充电
    if [ -z "$cur" ]; then cur=$D/sessions/$now.csv; echo "${cur##*/}" > $D/current; fi
    echo "$now,$(cat $BAT/capacity),$(cat $BAT/voltage_now),$(cat $BAT/current_now),$( [ -f $D/soft_on ] && [ -f $D/real_temp ] && cat $D/real_temp || cat $BAT/temp)" >> $cur
    last=$now
    [ $((now-lt)) -ge 5 ] && { lt=$now; dbg; }
    INT=$(cat $D/interval 2>/dev/null); [ -n "$INT" ] || INT=5
    sleep $INT
  else
    # 拔掉充电器：记录放电日志；插着充电器但没在充（充满 / 断充）不算放电
    on=$(cat $USB/online 2>/dev/null)
    if [ "$on" = 1 ] || [ "$st" = "Full" ]; then [ -n "$dcur" ] && dlog_end 插入充电器
    else
      [ -z "$dcur" ] && dlog_start
      c=$(cat $BAT/capacity 2>/dev/null); c=${c:-100}
      if [ $c -le 2 ]; then DI=5; elif [ $c -le 10 ]; then DI=10; elif [ $c -le 20 ]; then DI=30; else DI=60; fi
      [ $((now-dlt)) -ge $DI ] && { dlt=$now; dlog_line; }
    fi
    # 断开超过 60 秒视为本次充电结束
    if [ -n "$cur" ] && [ $((now-last)) -gt 60 ]; then summarize "$cur"; cur=""; rm -f $D/current; fi
    if [ -n "$cur" ] || [ "${c:-100}" -le 10 ]; then sleep 5; else sleep 20; fi
  fi
done
