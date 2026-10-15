SKIPUNZIP=0
# 机型校验：只允许小米15（dada）。移植系统 product 属性可能被改，vendor/odm 底包属性和 /vendor/build.prop 仍是 dada
isdada(){
  for k in ro.product.vendor.device ro.product.odm.device ro.product.device ro.product.board ro.product.vendor.name ro.product.mod_device ro.build.product; do
    case "$(getprop $k)" in dada|dada_*) return 0;; esac; done
  grep -qE '^ro\.product\.(vendor\.)?(device|name)=dada' /vendor/build.prop /odm/etc/build.prop 2>/dev/null
}
if ! isdada; then
  ui_print "********************"
  ui_print " ! 机型不符：本模块只适用于小米15（dada）"
  ui_print " ! 当前设备：$(getprop ro.product.marketname) $(getprop ro.product.vendor.device)"
  ui_print "********************"
  abort " ! 已取消安装，未做任何修改"
fi
D=/data/adb/mi_charge_boost
mkdir -p $D/sessions
# 从旧 ID（mi_charge_monitor）迁移：接管 dtbo 原版备份和写入状态，
# 防止以后卸载充电监控时把本模块写入的 dtbo 还原掉
O=/data/adb/mi_charge_monitor
if [ -d $O/dtbo ]; then
  mkdir -p $D/dtbo; cp -an $O/dtbo/. $D/dtbo/ 2>/dev/null
  rm -f $O/dtbo/state_a $O/dtbo/state_b $O/dtbo/state
fi
for f in interval shutdown_mv; do [ -f $O/$f ] && [ ! -f $D/$f ] && cp $O/$f $D/$f; done
[ -d $O/sessions ] && [ -z "$(ls $D/sessions 2>/dev/null)" ] && { cp -a $O/sessions/. $D/sessions/ 2>/dev/null; [ -f $O/index.csv ] && cp $O/index.csv $D/; }
rm -f $D/detail.list $D/ps.cache
getkey(){
  # 返回 up / down / none（15 秒无操作）
  t=0
  while [ $t -lt 15 ]; do
    ev=$(timeout 1 getevent -lqc 1 2>/dev/null)
    case "$ev" in
      *KEY_VOLUMEUP*DOWN*) echo up; return;;
      *KEY_VOLUMEDOWN*DOWN*) echo down; return;;
    esac
    t=$((t+1))
  done
  echo none
}
# 输出记录：KernelSU / APatch 安装页支持清屏指令，选择时整页重绘，
# 光标直接在选项上移动，不追加多余行；Magisk 等不支持时退回逐行追加
# 清屏重绘时连同 KernelSU 自己输出的开头一起补回（Logo、模块大小、安装路径等）
LOG=""
if [ "$KSU" = true ] && [ "$APATCH" != true ]; then
  SZ=$(unzip -l "$ZIPFILE" 2>/dev/null | tail -1 | awk '{printf "%.2f MB", $1/1000000}')
  SL=${SLOT:-$(getprop ro.boot.slot_suffix)}
  NM=$(grep_prop name $MODPATH/module.prop 2>/dev/null); [ -n "$NM" ] || NM=小米15充电加速
  AU=$(grep_prop author $MODPATH/module.prop 2>/dev/null); [ -n "$AU" ] || AU=酷安@鱼楠
  LOG=$(cat <<'EOF'
 _  __                    _ ____  _   _
| |/ /___ _ __ _ __   ___| / ___|| | | |
| ' // _ \ '__| '_ \ / _ \ \___ \| | | |
| . \  __/ |  | | | |  __/ |___) | |_| |
|_|\_\___|_|  |_| |_|\___|_|____/ \___/
EOF
)
  # 星号长度照 KernelSU 的 print_title：取两行字节数较大者 + 2
  bar(){ a=$(printf '%s' "$1" | wc -c); b=$(printf '%s' "$2" | wc -c); [ $a -gt $b ] && b=$a; printf "%$((b+2))s" | tr ' ' '*'; }
  B1=$(bar "$NM" "by $AU"); B2=$(bar "Powered by KernelSU" "")
  LOG="$LOG

- Module size: $SZ
- Installing to $MODPATH
- Extracting module files
- Running module installer
- Current boot slot: $SL
- Device is system-as-root
$B1
 $NM
 by $AU
$B1
$B2
 Powered by KernelSU
$B2
- Extracting module files
"
fi
out(){ ui_print "$1"; LOG="$LOG$1
"; }
REDRAW=0; { [ "$KSU" = true ] || [ "$APATCH" = true ]; } && REDRAW=1
CLR=$(printf '\033[H\033[J')
draw(){ # 重绘：已有内容 + 当前菜单（$1 = 当前项，$2 = 标记）
  ui_print "$CLR"
  printf '%s' "$LOG" | while IFS= read -r l; do ui_print "$l"; done
  i=1; for o in $OPTS; do o=$(echo "$o" | tr '\037' ' ')
    if [ $i = $1 ]; then ui_print "  $2 $i. $o"; else ui_print "     $i. $o"; fi; i=$((i+1)); done
}
# menu <步骤> <标题> <说明> <选项...>：音量+ 切换，音量- 确认，15 秒无操作选当前项（默认第一项）
menu(){
  st=$1; tt=$2; ds=$3; shift 3; n=$#; idx=1
  OPTS=""; for o in "$@"; do OPTS="$OPTS $(echo "$o" | tr ' ' '\037')"; done
  out " "; out "【第 $st 步】$tt"; [ -n "$ds" ] && out "  $ds"
  if [ $REDRAW = 1 ]; then
    draw 1 "▶"
    while true; do
      case "$(getkey)" in
        up) idx=$((idx+1)); [ $idx -gt $n ] && idx=1; draw $idx "▶";;
        *) break;;
      esac
      sleep 0.2
    done
    i=1; for o in "$@"; do LOG="$LOG     $i. $o
"; i=$((i+1)); done
    eval "cur=\$$idx"; OPTS=""; draw 0 ""; out "  ✔ 已选：$cur"
  else
    i=1; for o in "$@"; do ui_print "   $i. $o"; i=$((i+1)); done
    eval "cur=\$$idx"; ui_print "  ▶ 当前：$idx. $cur"
    while true; do
      case "$(getkey)" in
        up) idx=$((idx+1)); [ $idx -gt $n ] && idx=1; eval "cur=\$$idx"; ui_print "  ▶ 当前：$idx. $cur";;
        *) break;;
      esac
      sleep 0.2
    done
    ui_print "  ✔ 已选：$cur"
  fi
  SEL=$idx
}
out "********************"
out " 小米15充电加速  by 酷安@鱼楠"
out "********************"
{ read -r SI_N; read -r SI_D; read -r SI_O; read -r SI_B; } <<EOF
$(sh $MODPATH/sysinfo.sh)
EOF
out "- 设备: $SI_N ($SI_D)　系统: $SI_O${SI_B:+（底包 $SI_B）}"
out "- 音量+ 切换　音量- 确认　15 秒不操作选默认"
IS_DADA=0; [ "$SI_D" = dada ] && IS_DADA=1
DI=-; DT=-; DV=-; DZ=-
if [ $IS_DADA = 1 ]; then
  menu 1 "dtbo 快充电流" "修改后全温段以该电流满速" "修改为 15.5A" "修改为 20.5A（90W 理论极限）" "不修改电流"
  case $SEL in 1) DI=15500;; 2) DI=20500;; esac
  menu 2 "dtbo 满速/断充温度" "设定温度以下满速，超过停充" "修改为 55°C" "不修改温度"
  [ $SEL = 1 ] && DT=55
  menu 3 "dtbo 内核关机电压" "电池电压降到该值才关机" "修改为 2900mV" "修改为 3000mV" "不修改关机电压"
  case $SEL in 1) DV=2900;; 2) DV=3000;; esac
  menu 4 "屏幕超频" "华星屏添加 132/144/155/165Hz 刷新率档位" "屏幕超频 165Hz" "不超频屏幕"
  [ $SEL = 1 ] && DZ=165
  S4=5
else
  out "- 非小米15 (dada)，跳过 dtbo 修改"; S4=1
fi
menu $S4 "低电量延迟关机" "电量锁定 2%、关闭 30 秒关机提示，电压降到设定值再关机" "启用低电量延迟关机" "不启用低电量延迟关机"
if [ $SEL = 1 ]; then MV=2800; [ "$DV" != - ] && MV=$DV; else MV=0; fi
echo $MV > $D/shutdown_mv
menu $((S4+1)) "公版 PPS 解锁" "第三方 PPS 充电头放行高功率快充，小米原装头不受影响" "关闭" "开启"
PPS=0; [ $SEL = 2 ] && PPS=1; echo $PPS > $D/pps
menu $((S4+2)) "充电监测软件" "配合小米15充电加速使用的充电监测 App（充电监测 v4.9，含公版 PPS 控制中心磁贴）" "安装充电检测软件" "不安装"
CM=$SEL
DR=0; DO=$D/dtbo.out; true > $DO 2>/dev/null || { DO=/dev/mcb_dtbo.out; true > $DO; }
if [ $IS_DADA = 1 ] && [ "$DI$DT$DV$DZ" != "----" ]; then
  chmod 755 $MODPATH/dtbo/dtbopatch
  sh $MODPATH/dtbo/apply.sh $DI $DV $DT $DZ > $DO 2>&1; DR=$?
  if [ $DR = 5 ]; then
    grep -v "^! " $DO | while read -r l; do out "$l"; done
    menu $((S4+3)) "原厂镜像校验未通过" "当前 dtbo 不是已收录的原厂镜像（官改包可能有小改动）。可备份当前 dtbo 并以它为底修改刷入，不逐项比对原厂值" "不刷入 dtbo" "以当前镜像修改刷入"
    if [ $SEL = 2 ]; then DTBO_CUR=1 sh $MODPATH/dtbo/apply.sh $DI $DV $DT $DZ > $DO 2>&1; DR=$?
    else echo "! 原厂镜像校验未通过，已选择不刷入" >> $DO; fi
  fi
  grep -q "^! " $DO && DR=1
fi
ui_print " "
ui_print "======== 确认结果 ========"
if [ $IS_DADA = 1 ] && [ "$DI$DT$DV$DZ" != "----" ]; then
  if [ $DR = 0 ]; then ui_print "✅ dtbo 刷入成功，重启生效"
  else ui_print "❌ dtbo 刷入失败，分区未改动"; ui_print "   原因: $(grep '^! ' $DO | tail -1 | sed 's/^! //')"; fi
fi
f(){ [ "$1" = - ] && echo 不修改 || echo "$1$2"; }
if [ $IS_DADA = 1 ]; then
  ui_print "- 快充电流: $(f $DI mA)　断充温度: $(f $DT °C)　关机电压: $(f $DV mV)"
  [ "$DZ" = 165 ] && ui_print "- 屏幕: 超频 165Hz" || ui_print "- 屏幕: 不超频"
  if [ "$DI$DT$DV$DZ" != "----" ]; then
    ui_print "- dtbo 写入过程:"; grep -v "^ERROR: bad vbmeta" $DO | while read -r l; do ui_print "  $l"; done
  else
    ui_print "- dtbo 不修改"
  fi
fi
[ $MV -gt 0 ] && ui_print "- 低电量延迟关机: 启用（${MV}mV，WebUI 可调）" || ui_print "- 低电量延迟关机: 不启用"
if [ $PPS = 1 ]; then
  if [ -d /data/adb/modules/FreePPS ] && [ ! -f /data/adb/modules/FreePPS/disable ]; then ui_print "- 公版 PPS 解锁: 开启，但已安装 FreePPS，本模块此项自动停用"
  else ui_print "- 公版 PPS 解锁: 开启（拔出充电器后放行，下次插入生效）"; [ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" = 1 ] || echo 1 > /sys/class/qcom-battery/pd_verifed 2>/dev/null; fi
else ui_print "- 公版 PPS 解锁: 关闭"; fi
if [ "$CM" = 1 ]; then
  A=$MODPATH/apk/charge_monitor.apk; T=/data/local/tmp/charge_monitor.apk
  inst(){ cd / && { cp $A $T 2>/dev/null && chmod 644 $T && pm install -r -g $T 2>&1; } || cat $A | pm install -r -g -S $(stat -c %s $A) 2>&1; }
  r=$(inst)
  case "$r" in *UPDATE_INCOMPATIBLE*|*SIGNATURES*) pm uninstall com.yunan.chargehub >/dev/null 2>&1; r=$(inst); ui_print "- 充电监测软件签名不同，已卸载旧版后重装";; esac; rm -f $T
  case "$r" in *Success*) ui_print "- 充电监测软件: 已安装";; *) touch $D/cm_pending; ui_print "- 充电监测软件: 现在装不上（$r），重启后自动安装";; esac
else ui_print "- 充电监测软件: 不安装"; fi
[ -f $D/cm_pending ] && { mkdir -p $D/apk; cp -f $MODPATH/apk/charge_monitor.apk $D/apk/; }
rm -rf $MODPATH/apk
# 高刷切换：接管旧的独立高刷切换模块（配置、日志迁移过来，旧模块重启后移除）
OH=/data/adb/modules/xiaomi15_hz_switch
[ -f /data/adb/xiaomi15_hz_switch.conf ] && [ ! -f $D/hz.conf ] && cp /data/adb/xiaomi15_hz_switch.conf $D/hz.conf
[ -f /data/adb/xiaomi15_hz_switch.history ] && [ ! -f $D/hz.history ] && cp /data/adb/xiaomi15_hz_switch.history $D/hz.history
if [ -d $OH ]; then touch $OH/remove; ui_print "- 已合并独立的「高刷切换」模块，旧模块重启后自动移除"; fi
ui_print "- 高刷切换: WebUI 底部「高刷切换」页点选 120/132/144/156/165Hz"
set_perm_recursive $MODPATH 0 0 0755 0755
ui_print "- 充电记录只在充电时写入，放电不记录"
ui_print "- 重启后生效；不想重启可在 WebUI 设置里点启动"
ui_print "- 致谢：酷安@低线阻狂魔、酷安@花橋桥（PPS 节点）"
ui_print "        酷安@瓦力喀 / FreePPS（思路参考）"
ui_print "        酷安@久保Sama / 刷新率APP（高刷切换思路）"
[ $IS_DADA = 1 ] && sh $MODPATH/dtbo/apply.sh desc >/dev/null 2>&1
[ "$DR" != 0 ] && sed -i "s|^description=|description=❌ DTBO 刷入失败（$(grep "^! " $D/dtbo.out | tail -1 | sed "s/^! //")） ｜ |" $MODPATH/module.prop
