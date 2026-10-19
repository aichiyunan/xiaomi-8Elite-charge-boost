#!/system/bin/sh
# 用法: apply.sh <电流mA> <关机电压mV> <断充温度°C> [165|-] [80|-] | restore | status
# 第 5 个参数：quick_chg_fv_hys，80=写入 80，-=写回 1（默认，原厂值）；本机 dtbo 没有该属性则跳过
# 第 4 项 165 = 屏幕超频 165Hz（华星 o3_42 屏添加 132/144/155/165Hz timing，仅小米15 dada）
# 小米私有协议功率：不走参数，读 /data/adb/mi_charge_boost/proto（机型可选档位见 models.sh PWO，其它=原厂），由 WebUI 开关写入
# v8.4.9 起多机型：机型参数见 ../models.sh；模板按原厂镜像头部哈希从 stock.list 选（<代号>_<布局>.tpl，dada 仍用 dada.tpl）
PF=${PROTO_F:-/data/adb/mi_charge_boost/proto}; PW=$(cat $PF 2>/dev/null); case "$PW" in 100|120) ;; *) PW=-;; esac
H=${0%/*}; D=${DTBO_D:-/data/adb/mi_charge_boost/dtbo}
MCB_ROOT=${H%/*}; . $MCB_ROOT/models.sh
# 数据目录必须可写：移植系统上可能出现属主/SELinux 标签不对导致 Permission denied，先修复，修不好换备用目录
okw(){ mkdir -p "$1" 2>/dev/null && touch "$1/.w" 2>/dev/null && rm -f "$1/.w"; }
F=/data/adb/.mcb_dtbo
if [ -z "$DTBO_D" ] && [ -f $F/stock.img ]; then D=$F
elif ! okw $D; then
  R=${D%/dtbo}; chattr -R -i $R 2>/dev/null; chown -R 0:0 $R 2>/dev/null; chmod -R u+rwX,go+rX $R 2>/dev/null
  chcon -R u:object_r:adb_data_file:s0 $R 2>/dev/null
  if ! okw $D; then
    if [ -z "$DTBO_D" ] && okw $F; then chcon -R u:object_r:adb_data_file:s0 $F 2>/dev/null; D=$F
    else echo "! 数据目录 $D 不可写（Permission denied）"; exit 1; fi
  fi
fi
S=$(getprop ro.boot.slot_suffix)
BLK=/dev/block/by-name/dtbo$S; [ -e $BLK ] || BLK=/dev/block/bootdevice/by-name/dtbo$S
[ -n "$DTBO_BLK" ] && BLK=$DTBO_BLK
[ -e $BLK ] || { echo "! 找不到 dtbo 分区"; exit 1; }
chmod 755 $H/dtbopatch
prep(){ # $1=I $2=T [$3=模板名]：Q: 行（按 OS3 重构的快充表，仅 dada.tpl 有）只在改了电流或温度时写入；{IQ}/{TQ} 未设定时用本机原厂上限 $MI/48
  iq=$1; [ "$iq" = - ] && iq=$MI; tq=$2; [ "$tq" = - ] && tq=48; tf=$H/${3:-$TPL}.tpl
  # 改了电流：全程按所选电流满速撑到本机 FFC 截止电压 $VQ（dada 4580，与 303 加速版一致）；没改电流：高压段保持原厂 16500/3780/4510
  if [ "$1" = - ]; then mq=$iq; [ $mq -gt 16500 ] && mq=16500; lq=3780; vq=4510; mv='{I}'; else mq=$1; lq=$1; vq=$VQ; mv=$1; fi
  # {S} 单电荷泵分支上限：所选电流封顶 $SC（dada 20000）；{IW} 降速温区改满速时用的电流：所选电流或本机原厂值
  sv='{I}'; [ "$1" = - ] || { sv=$1; [ $1 -ge $SC ] && sv=$SC; }; iw=$iq
  if [ "$1$2" = "--" ]; then grep -v '^Q:' $tf; else sed 's/^Q://' $tf; fi | sed "s/{IQ}/$iq/g; s/{TQ}/$tq/g; s/{S}/$sv/g; s/{MQ}/$mq/g; s/{LQ}/$lq/g; s/{VQ}/$vq/g; s/{M}/$mv/g; s/{IW}/$iw/g"
}
sha(){ dd if="$1" bs=4096 count=$2 2>/dev/null | sha256sum | cut -d' ' -f1; }
hsha(){ # 只算 DT table 头部 total_size 长度的 sha256，与分区大小、尾部填充、AVB 尾部无关
  [ "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" = d7b7ab1e ] || return 1
  n=$((0x$(dd if="$1" bs=1 skip=4 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')))
  [ "$n" -gt 0 ] || return 1; head -c $n "$1" | sha256sum | cut -d' ' -f1; }
# 旧版快充表布局（OS3.0.2–3.0.303 等 HyperOS 2 底包，没有 *_volt_para*_4/_5）：
# vstep_para 格式不同保持原厂，_4/_5 表不存在不写；以下属性原厂值与新版不同，按模板整体覆盖
ALLOW='^mismatch +(mca_strategy_quick_charge/(temp_para[12]|(normal|ffc)_volt_para[12]_[23]|ffc_stage_para2_3|div_max_curr|div_single_curr)|mca_quick_charge_batt_para_gbl/.*)$'
oldtpl(){ grep -vE '^(Q:)?mca_strategy_quick_charge	(vstep_para|(normal|ffc)_volt_para[12]_[45])	'; }
dropallow(){ # 没改电流/温度时旧布局的快充分段全部保持原厂
  grep -vE '^(Q:)?(mca_strategy_quick_charge	(temp_para[12]|(normal|ffc)_volt_para[12]_[23]|ffc_stage_para2_3|div_max_curr|div_single_curr)|mca_quick_charge_batt_para_gbl	[^	]+)	'; }
isold(){ # $1=镜像：用完整模板试跑，快充表 _4 缺失即为旧布局（只有小米15 dada.tpl 有新旧两种布局）
  [ "$TPL" = dada ] || return 1
  prep 15500 58 > $TMP/lay.tpl; DTBO_SET=I=15500,V=2700,T=58,L=48 $H/dtbopatch "$1" $TMP/lay.tpl - 2>&1 | grep -qE '^missing +mca_strategy_quick_charge/normal_volt_para1_4$'; }
oldok(){ # $1=日志：旧布局下只有允许的属性不一致、没有缺失
  grep -qE "missing=0 " "$1" || return 1
  ! grep -E '^mismatch ' "$1" | grep -vqE "$ALLOW"; }
bestt(){ # 非原厂底包：在本机型各布局模板里试跑，选没有缺失、不一致最少的（dada 固定 dada.tpl）
  [ "$CODE" = dada ] && { echo dada; return; }
  bt=$DEFT; bm=99999
  for f in $(ls -r $H/${CODE}_*.tpl); do t=${f##*/}; t=${t%.tpl}; prep $I $T $t > $TMP/bt.tpl; cp $AVB $TMP/bt.avb
    r=$(DTBO_SET=I=$I,V=$V,T=$T,L=$L $H/dtbopatch "$1" $TMP/bt.tpl - 2>&1 | grep '^SUMMARY')
    case "$r" in *" missing=0 "*) m=${r#*mismatch=}; m=${m%% *}; [ "$m" -lt "$bm" ] && { bm=$m; bt=$t; };; esac
  done; echo $bt; }
nb(){ echo $(( $(stat -c %s "$1") / 4096 )); }
write(){ # 文件 -> 分区并校验
  n=$(nb "$1"); [ "$n" -gt 0 ] || { echo "! 文件为空"; return 1; }; want=$(sha "$1" $n)
  blockdev --setrw $BLK 2>/dev/null
  dd if="$1" of=$BLK bs=1048576 conv=fsync 2>/dev/null; sync
  [ "$(sha $BLK $n)" = "$want" ] || { echo "! 写入校验失败"; return 1; }
  echo "$want $n" > $D/written$S
}
desc(){ # 把 dtbo 状态写进模块描述，模块列表里直接可见
  P=${H%/*}/module.prop; [ -f "$P" ] || return 0
  g(){ [ "$1" = - ] && echo 原厂 || echo "$1$2"; }
  st=$(sh $H/apply.sh status 2>/dev/null); set -- $st
  bt=$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) )); wt=$(stat -c %Y $D/written$S 2>/dev/null || echo 0)
  case "$1" in
    mod) v="$(g $2 mA) / $(g $4 °C) / $(g $3 mV)"; [ "$5" = 165 ] && v="$v / 屏幕 165Hz"; [ "${6:--}" != - ] && v="$v / 协议 ${6}W"; [ "${7:--}" = 80 ] && v="$v / fv_hys 80"
         if [ "$wt" -gt "$bt" ]; then t="⏳ DTBO 已写入 $v，重启生效"; else t="✅ DTBO 已生效 $v"; fi;;
    stock) if [ "$wt" -gt "$bt" ]; then t="⏳ DTBO 已还原原版，重启生效"; else t="DTBO 原版（未修改）"; fi;;
    changed) t="⚠️ DTBO 已被还原，之前的修改已失效";;
    *) t="DTBO 未修改";;
  esac
  m=$(cat /data/adb/mi_charge_boost/shutdown_mv 2>/dev/null)
  [ -n "$m" ] && [ "$m" != 0 ] && t="$t ｜ 低电量延迟关机 ${m}mV" || t="$t ｜ 低电量延迟关机 关"
  if [ "$(cat /data/adb/mi_charge_boost/pps 2>/dev/null)" = 1 ]; then
    if [ -d /data/adb/modules/FreePPS ] && [ ! -f /data/adb/modules/FreePPS/disable ]; then t="$t ｜ ⚡ 公版PPS 让给 FreePPS"
    else l=$(cat /data/adb/mi_charge_boost/pps_last 2>/dev/null); t="$t ｜ ⚡ 公版PPS 开（内置 FreePPS）${l:+（上次 ${l}W 头）}"; fi
  else t="$t ｜ 公版PPS 关"; fi
  sed -i "s|^description=.*|description=$t ｜ 致谢：酷安@低线阻狂魔、酷安@花橋桥（PPS 节点）、内置 FreePPS（Seyud / 酷安@瓦力喀，GPL-3.0）|" "$P"
}
case "$1" in
desc) desc; exit 0;;
status)
  [ -f $D/conf ] && read I V T Z P FH < $D/conf
  if [ -f $D/written$S ]; then read W N < $D/written$S
    if [ "$(sha $BLK $N)" = "$W" ]; then
      if [ -f $D/conf ] && [ "$(cat $D/state$S 2>/dev/null)" = "mod" ]; then echo "mod $I $V ${T:-58} ${Z:--} ${P:--} ${FH:--}"; else echo "stock"; fi; exit 0; fi
    rm -f $D/stock.img $D/stock_src $D/written$S $D/state$S; echo "changed $I $V ${T:-58}"; exit 0; fi
  echo "none"; exit 0;;
restore)
  [ -f $D/stock.img ] || { echo "! 没有原版备份"; exit 1; }
  write $D/stock.img || exit 1; echo stock > $D/state$S; rm -f $PF
  echo "- 已写回原版 dtbo，重启生效"; desc; exit 0;;
esac
{ read -r SI_N; read -r SI_D; read -r SI_O; read -r SI_B; } <<EOF
$(sh $H/../sysinfo.sh)
EOF
CODE=$SI_D
model_info "$CODE" || { echo "! 不支持的机型 $SI_N ($SI_D)，已适配：$(model_names)"; exit 1; }
I=${1:--}; V=${2:--}; T=${3:--}; Z=${4:--}; FH=${5:--}
case "$Z" in 165|-) ;; *) echo "! 屏幕超频参数只能是 165 或 -"; exit 1;; esac
case "$FH" in 80|-) ;; *) echo "! quick_chg_fv_hys 参数只能是 80 或 -"; exit 1;; esac
[ "$Z" = 165 ] && [ "$HZ" != 1 ] && { echo "! 屏幕超频 165Hz 只支持小米15（华星 o3_42 屏），$MN 不支持"; exit 1; }
# 私有协议档位只接受本机可选值（原厂已是 120W 的 K80 Pro 没有可选档）
[ "$PW" != - ] && case " $PWO " in *" $PW "*) ;; *) echo "- 私有协议 ${PW}W 不适用于 $MN（原厂 ${PW0}W），忽略"; PW=-; rm -f $PF;; esac
for x in "$I" "$V" "$T"; do case "$x" in -) ;; *[!0-9]*|"") echo "! 参数错误"; exit 1;; esac; done
[ "$I$V$T$Z$PW$FH" = "------" ] && { echo "- 都不修改，跳过写入"; exit 0; }
echo "- 机型: $SI_N ($SI_D)　系统: $SI_O${SI_B:+（底包 $SI_B）}"
[ "$I" = - ] || { [ $I -ge 9000 ] && [ $I -le $MX ] || { echo "! 电流范围 9000-$MX mA"; exit 1; }; }
[ "$V" = - ] || { [ $V -ge 2400 ] && [ $V -le 3400 ] || { echo "! 关机电压范围 2400-3400 mV"; exit 1; }; }
L=-
[ "$T" = - ] || { [ $T -ge 45 ] && [ $T -le 58 ] || { echo "! 温度范围 45-58°C"; exit 1; }; L=48; [ $((T-3)) -lt 48 ] && L=$((T-3)); }
# 临时目录：优先 /dev（tmpfs，不受 /data 权限、移植系统 SELinux 影响），失败再退回数据目录
TMP=; for b in /dev /data/local/tmp $D; do t=$b/mcb_dtbo.$$; rm -rf $t; mkdir -p $t 2>/dev/null && touch $t/.w 2>/dev/null && { TMP=$t; break; }; done
[ -n "$TMP" ] || { echo "! 无法创建临时目录（/dev、/data/local/tmp、$D 都不可写）"; exit 1; }
trap 'cd /; rm -rf $TMP' EXIT; cd /
# 移植系统的 dtbo 可能没有 AVB 尾部：给每个模板配上原厂 AVB 模板（算法 NONE，只更新哈希）
AVB=$H/$CODE.avb; [ -f $AVB ] || AVB=$H/dada.avb
for n in r chk lay; do cp $AVB $TMP/$n.avb; done
if [ ! -f $D/stock.img ]; then
  dd if=$BLK of=$TMP/cur.img bs=1048576 2>/dev/null
  HS=$(hsha $TMP/cur.img); KV=; TP=; [ -n "$HS" ] && { set -- $(grep "^$HS " $H/stock.list 2>/dev/null | head -1); }
  if [ -n "$HS" ] && [ -n "$2" ]; then
    # stock.list：哈希 代号 模板 版本；只接受本机型自己的原厂镜像
    if [ "$2" != "$CODE" ]; then model_info "$2" >/dev/null && o=$MN || o=$2; model_info "$CODE"
      echo "! 当前 dtbo 是 $o 的原厂镜像（$4），与本机 $MN 不符，拒绝写入"; rm -rf $TMP; exit 1; fi
    TP=$3; KV=$4
  fi
  U=$H/unmod_$(echo "$HS" | cut -c1-8).rules
  [ "$CODE" = dada ] || U=/nonexistent
  if [ -z "$KV" ] && [ -n "$HS" ] && [ -f "$U" ]; then
    # 已收录的“预改”dtbo（移植包自带改过的充电参数）：先还原成对应原厂值，比对通过才当作原厂备份
    cp $TMP/cur.img $D/orig_port.img 2>/dev/null
    cp $H/dada.avb $TMP/u.avb; cp "$U" $TMP/u.rules; TP=dada
    if $H/dtbopatch $TMP/cur.img $TMP/u.rules $TMP/un.img > $TMP/un.log 2>&1 && prep 15500 58 dada > $TMP/chk.tpl && DTBO_SET=I=15500,V=2700,T=58,L=48 $H/dtbopatch $TMP/un.img $TMP/chk.tpl - > $TMP/chk.log 2>&1 && grep -q "done=0 mismatch=0 missing=0" $TMP/chk.log; then
      l=$(sed -n '1s/^# *//p' "$U"); KV="${l%%：*}（预改参数已还原为 OS4.0.0.19 原厂值）"; mv $TMP/un.img $TMP/cur.img
    else echo "! 预改 dtbo 还原失败：$(grep -E 'ERROR|SUMMARY' $TMP/un.log $TMP/chk.log 2>/dev/null | tail -1)"; exit 1; fi
  fi
  if [ -n "$KV" ]; then
    cp $TMP/cur.img $D/stock.img && [ "$(sha $D/stock.img 1)" = "$(sha $TMP/cur.img 1)" ] || { echo "! 原版备份写入 $D 失败"; exit 1; }
    rm -f $D/stock_src; echo "$CODE $TP" > $D/tpl
    echo "- 哈希匹配原厂 $KV dtbo，已备份 → $D/stock.img"
  elif [ "$DTBO_CUR" = 1 ]; then
    # 原厂校验未通过（官改包等），用户选择以当前 dtbo 为底：备份当前分区，直接覆盖写入，不逐项比对原厂值
    [ "$(head -c 4 $TMP/cur.img | od -An -tx1 | tr -d ' \n')" = d7b7ab1e ] || { echo "! 当前 dtbo 分区不是 DT table 格式"; exit 1; }
    cp $TMP/cur.img $D/stock.img && [ "$(sha $D/stock.img 1)" = "$(sha $TMP/cur.img 1)" ] || { echo "! 当前 dtbo 备份写入 $D 失败"; exit 1; }
    echo cur > $D/stock_src; echo "$CODE $(bestt $TMP/cur.img)" > $D/tpl
    echo "- 原厂校验未通过，按选择以当前 dtbo 为底修改（头部哈希 ${HS:-无法读取}），已备份 → $D/stock.img"
  else
    mkdir -p /sdcard/Download 2>/dev/null; cp $TMP/cur.img /sdcard/Download/dtbo_当前分区.img 2>/dev/null && echo "  已导出当前分区 → /sdcard/Download/dtbo_当前分区.img，可发给作者收录"
    echo "  分区: $BLK  头部哈希: ${HS:-无法读取}"
    echo "! 原厂镜像校验未通过：当前 dtbo 不是已收录的原厂镜像（官改包可能有小改动）"
    rm -rf $TMP; exit 5
  fi
else
  [ "$(cat $D/stock_src 2>/dev/null)" = cur ] && echo "- 已有当前 dtbo 备份（非原厂，以当前镜像为底），沿用 $D/stock.img" || echo "- 已有原厂备份，沿用 $D/stock.img"
fi
# 备份对应的模板：v8.4.9 起备份时记在 $D/tpl（"代号 模板"）；旧版本的备份只可能来自小米15 → dada.tpl
TPL=; if [ -f $D/tpl ]; then read c t < $D/tpl
  [ "$c" = "$CODE" ] || { echo "! 已有的 dtbo 备份属于 $c，与本机 $CODE 不符，请先删除 $D 后重试"; rm -rf $TMP; exit 1; }; TPL=$t
else
  set -- $(grep "^$(hsha $D/stock.img) " $H/stock.list 2>/dev/null | head -1)
  if [ -n "$2" ]; then [ "$2" = "$CODE" ] || { echo "! 已有的 dtbo 备份是 $2 的原厂镜像，与本机 $CODE 不符"; rm -rf $TMP; exit 1; }; TPL=$3
  elif [ "$CODE" = dada ]; then TPL=dada; else TPL=$DEFT; fi
  echo "$CODE $TPL" > $D/tpl
fi
[ -f $H/$TPL.tpl ] || { echo "! 缺少模板 $TPL.tpl"; rm -rf $TMP; exit 1; }
[ "$TPL" = dada ] || echo "- 机型模板: $TPL（快充/温控表按本机原厂值，FFC 截止电压 ${VQ}mV 不改）"
: > $TMP/r.tpl
[ "$I$V$T" = "---" ] || prep $I $T >> $TMP/r.tpl
[ "$Z" = 165 ] && { cat $H/hz165.tpl >> $TMP/r.tpl; echo "- 屏幕超频：添加 132/144/155/165Hz timing"; }
FORCE=
# 以当前镜像为底：不逐项比对原厂值，属性存在就直接覆盖为目标值
[ "$(cat $D/stock_src 2>/dev/null)" = cur ] && { FORCE=-force; echo "- 非原厂底包：跳过原厂值逐项比对，直接覆盖写入"; }
if isold $D/stock.img && [ -s $TMP/r.tpl ]; then
  if [ "$I$T" = "--" ]; then oldtpl < $TMP/r.tpl | dropallow > $TMP/r2.tpl; echo "- 旧版快充表布局：未改电流/温度，快充表保持原厂"
  else oldtpl < $TMP/r.tpl > $TMP/r2.tpl; echo "- 旧版快充表布局：升流步进保持原厂，按新表覆盖快充分段"; fi
  mv $TMP/r2.tpl $TMP/r.tpl
  DTBO_SET=I=$I,V=$V,T=$T,L=$L $H/dtbopatch $D/stock.img $TMP/r.tpl - > $TMP/dry 2>&1
  [ -n "$FORCE" ] || { oldok $TMP/dry && FORCE=-force; }
fi
if [ -s $TMP/r.tpl ]; then
  DTBO_SET=I=$I,V=$V,T=$T,L=$L $H/dtbopatch $D/stock.img $TMP/r.tpl $TMP/new.img $FORCE > $TMP/log 2>&1
  rc=$?; grep -E "SUMMARY|ERROR|missing " $TMP/log
  [ $rc = 4 ] && [ "$Z" = 165 ] && grep -q "missing  *+" $TMP/log && echo "! 没找到华星 o3_42 屏幕节点，此机型/屏幕不支持超频"
else
  cp $D/stock.img $TMP/new.img; rc=0
fi
[ $rc = 0 ] || { echo "! 生成失败，分区未改动"; rm -rf $TMP; exit 1; }
if [ "$PW" != - ]; then
  # 小米私有协议功率：单独一遍，属性存在即覆盖（参考 K80 Pro：PD 协议 max_power 120W、快充 max_power 120000）
  printf 'mca_protocol_pd_class\tmax_power\t0000005a\tw\t%s\nmca_strategy_quick_charge\tmax_power\t00015f90\tw\t%s\n' $PW ${PW}000 > $TMP/p.tpl
  # K90 至尊版另有 strategy_quick_charge_override（含 max_power），存在就一起改
  [ "$CODE" = warsaw ] && printf '?strategy_quick_charge_override\tmax_power\t000186a0\tw\t%s\n' ${PW}000 >> $TMP/p.tpl
  cp $AVB $TMP/p.avb
  DTBO_SET=I=$I,V=$V,T=$T,L=$L $H/dtbopatch $TMP/new.img $TMP/p.tpl $TMP/new2.img -force > $TMP/plog 2>&1; prc=$?
  grep -E "SUMMARY|ERROR|missing " $TMP/plog
  if [ $prc = 0 ] && ! grep -q "^missing " $TMP/plog; then mv $TMP/new2.img $TMP/new.img; echo "- 小米私有协议：${PW}W"
  else echo "! 协议功率节点写入失败，分区未改动"; rm -rf $TMP; exit 1; fi
fi
# quick_chg_fv_hys：单独一遍，属性存在即覆盖；开关打开写 80，关闭写回 1（各机型原厂均为 1，非原厂底包上也能改回）
FV=1; [ "$FH" = 80 ] && FV=80
printf 'mca_strategy_quick_charge\tquick_chg_fv_hys\t00000001\tw\t%s\n' $FV > $TMP/f.tpl; cp $AVB $TMP/f.avb
DTBO_SET=I=$I,V=$V,T=$T,L=$L $H/dtbopatch $TMP/new.img $TMP/f.tpl $TMP/new3.img -force > $TMP/flog 2>&1; frc=$?
if [ $frc = 4 ] || grep -q "^missing " $TMP/flog; then [ "$FH" = 80 ] && echo "- 本机 dtbo 没有 quick_chg_fv_hys，跳过"; FH=-
elif [ $frc = 0 ] && [ -s $TMP/new3.img ]; then mv $TMP/new3.img $TMP/new.img; echo "- quick_chg_fv_hys：$FV"
elif [ $frc = 2 ]; then echo "- quick_chg_fv_hys：$FV（已是该值）"
else grep -E "SUMMARY|ERROR" $TMP/flog; echo "! quick_chg_fv_hys 写入失败，分区未改动"; rm -rf $TMP; exit 1; fi
write $TMP/new.img || { rm -rf $TMP; exit 1; }
echo "$I $V $T $Z $PW $FH" > $D/conf; echo mod > $D/state$S
rm -rf $TMP
f(){ [ "$1" = - ] && echo 不修改 || echo "$1$2"; }
desc
zz=不超频; [ "$Z" = 165 ] && zz=165Hz
pp=原厂${PW0}W; [ "$PW" = - ] || pp=${PW}W
fh=1; [ "$FH" = 80 ] && fh=80
echo "- 已写入：充电电流 $(f $I mA)，关机电压 $(f $V mV)，断充温度 $(f $T °C)，屏幕 $zz，私有协议 $pp，fv_hys $fh，重启生效"
