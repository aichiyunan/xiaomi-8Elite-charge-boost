#!/system/bin/sh
# 已适配机型表（v8.4.9 起多机型）：代号 → 参数
# MN 机型名  MI 原厂快充电流(mA)  MX 模块允许的电流上限  SC 单电荷泵分支上限(div_single_curr)
# VQ 满电 FFC 截止电压(mV，模块不改，只用于重构表/显示)  V0 原厂关机电压  PW0 原厂私有协议功率  PWO 可选协议功率
# HZ 1=支持屏幕超频 165Hz/高刷切换（只有小米15 华星 o3_42 屏）  DEFT 非原厂底包时用的模板
MODELS="dada haotian miro annibale warsaw"
model_info(){
  case "$1" in
    dada)     MN=小米15;          MI=15500; MX=20500; SC=20000; VQ=4580; V0=3050; PW0=90;  PWO="100 120"; HZ=1; DEFT=dada;;
    haotian)  MN="小米15 Pro";    MI=15600; MX=20500; SC=20000; VQ=4580; V0=3050; PW0=90;  PWO="100 120"; HZ=0; DEFT=haotian_os4;;
    miro)     MN="红米K80 Pro";   MI=20500; MX=22000; SC=20500; VQ=4550; V0=3050; PW0=120; PWO="";        HZ=0; DEFT=miro_os4;;
    annibale) MN=红米K90;         MI=17600; MX=20500; SC=20000; VQ=4550; V0=2850; PW0=100; PWO="120";     HZ=0; DEFT=annibale_os4;;
    warsaw)   MN=红米K90至尊版;   MI=17600; MX=20500; SC=20000; VQ=4560; V0=2850; PW0=100; PWO="120";     HZ=0; DEFT=warsaw_os4b;;
    *) return 1;;
  esac
  MODNAME="${MN}充电加速模块"; return 0
}
model_names(){ echo "小米15 / 小米15 Pro / 红米K80 Pro / 红米K90 / 红米K90至尊版"; }
# 识别机型代号：sysinfo.sh（移植系统优先读 vendor/odm）→ 其它属性 → 分区 build.prop
detect_code(){
  c=$(sh ${MCB_ROOT:-${0%/*}}/sysinfo.sh 2>/dev/null | sed -n 2p)
  model_info "$c" >/dev/null 2>&1 && { echo $c; return 0; }
  for k in ro.product.vendor.device ro.product.odm.device ro.product.device ro.product.board ro.product.vendor.name ro.product.mod_device ro.build.product; do
    v=$(getprop $k); v=${v%%_*}; model_info "$v" >/dev/null 2>&1 && { echo $v; return 0; }; done
  for m in $MODELS; do
    grep -qE "^ro\.product\.(vendor\.)?(device|name)=${m}(_|\$)" /vendor/build.prop /odm/etc/build.prop 2>/dev/null && { echo $m; return 0; }; done
  echo "${c:-unknown}"; return 1
}
# 运行时取机型：安装时写入 $MCB_ROOT/model，没有再现场识别
model_code(){ r=${MCB_ROOT:-/data/adb/modules/mi_charge_boost}; c=$(cat $r/model 2>/dev/null)
  model_info "$c" >/dev/null 2>&1 && { echo $c; return 0; }; MCB_ROOT=$r detect_code; }
