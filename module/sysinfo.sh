#!/system/bin/sh
# 输出四行：机型名 / 机型代号 / 系统 / 底包（vendor 固件版本，dtbo 跟它走）
# 兼容移植系统（ColorOS 等）：ro.product.* 可能被改成别家，优先读 vendor/odm 分区
g(){ for p; do v=$(getprop $p); [ -n "$v" ] && { echo "$v"; return; }; done; }
DEV=$(g ro.product.vendor.device ro.product.odm.device ro.product.device)
# 已适配机型（dada / haotian / miro / annibale / warsaw）：任一 device 属性是已适配代号就以它为准，vendor/odm 优先（dtbo 跟底包走）
SUP=" dada haotian miro annibale warsaw "
case "$SUP" in *" $DEV "*) ;; *) for p in ro.product.vendor.device ro.product.odm.device ro.product.device ro.product.system.device; do v=$(getprop $p); case "$SUP" in *" $v "*) DEV=$v; break;; esac; done;; esac
# 机型名：vendor/odm 优先（移植包常把 system 的 ro.product.* 改成「Xiaomi for arm64」之类的通用值）
bad(){ case "$1" in ""|*" for arm64"*|*" for arm"*|*[Gg]eneric*|*AOSP*|*aosp*|mainline*|qssi*) return 0;; esac; return 1; }
gn(){ for p; do v=$(getprop $p); bad "$v" || { echo "$v"; return; }; done; }
NAME=$(gn ro.product.vendor.marketname ro.product.odm.marketname ro.vendor.oplus.market.name ro.product.marketname)
if [ -z "$NAME" ]; then
  for f in /vendor/build.prop /odm/etc/build.prop /vendor/odm/etc/build.prop; do
    v=$(grep -m1 -E '^ro\.product\.(vendor|odm)\.marketname=' $f 2>/dev/null | cut -d= -f2-); bad "$v" || { NAME=$v; break; }; done
fi
if [ -z "$NAME" ]; then case "$DEV" in
  dada) NAME="Xiaomi 15";; haotian) NAME="Xiaomi 15 Pro";; miro) NAME="REDMI K80 Pro";; annibale) NAME="REDMI K90";; warsaw) NAME="REDMI K90 至尊版";;
  *) NAME=$(gn ro.product.vendor.model ro.product.odm.model ro.product.model);; esac; fi
OPL=$(getprop ro.build.version.oplusrom.display); [ -n "$OPL" ] || OPL=$(getprop ro.build.version.oplusrom)
MI=$(g ro.mi.os.version.incremental)
INC=$(getprop ro.build.version.incremental)
if [ -n "$OPL" ]; then OS="ColorOS ${OPL#V}"
elif [ -n "$MI" ]; then OS="$MI"
else case "$INC" in OS*|V*) OS="$INC";; *) OS=$(g ro.build.display.id ro.build.version.incremental);; esac; fi
# 底包：移植系统常把 vendor 属性覆盖成别家值，依次查属性、指纹、分区 build.prop 原文，取第一个 HyperOS/MIUI 版本号
pick(){ grep -oE '(OS[0-9]+(\.[0-9]+)+\.[A-Z]+|V[0-9]+(\.[0-9]+)+\.[A-Z]+)' | head -1; }
BASE=
for p in ro.vendor.build.version.incremental ro.odm.build.version.incremental ro.vendor_dlkm.build.version.incremental ro.mi.os.version.incremental ro.vendor.build.fingerprint ro.odm.build.fingerprint ro.bootimage.build.fingerprint; do
  BASE=$(getprop $p | pick); [ -n "$BASE" ] && break; done
[ -n "$BASE" ] || for f in /vendor/build.prop /odm/etc/build.prop /vendor/odm/etc/build.prop /vendor_dlkm/etc/build.prop; do
  BASE=$(grep -E '^ro\.(vendor|odm|vendor_dlkm)\.build\.(version\.incremental|fingerprint)=' $f 2>/dev/null | pick); [ -n "$BASE" ] && break; done
# 底包显示规则：system 是 HyperOS/MIUI 且 vendor、odm 也都是 HyperOS/MIUI 时不显示；识别到非 HyperOS 的 system（移植包）才显示
hv(){ echo "$1" | grep -qE '(^|[^0-9A-Za-z])(OS[0-9]+(\.[0-9]+)+\.[A-Z]+|V[0-9]+(\.[0-9]+)+\.[A-Z]+)'; }
pv(){ v=; for p; do v=$(getprop $p); [ -n "$v" ] && break; done; [ -n "$v" ] || v=$(grep -hm1 -E "^($(echo "$*" | sed 's/ /|/g' | sed 's/\./\\./g'))=" /vendor/build.prop /odm/etc/build.prop /vendor/odm/etc/build.prop 2>/dev/null | cut -d= -f2-); echo "$v"; }
VND=$(pv ro.vendor.build.version.incremental ro.vendor.build.fingerprint)
ODM=$(pv ro.odm.build.version.incremental ro.odm.build.fingerprint)
SYSHY=0
if [ -z "$OPL" ] && [ -z "$(getprop ro.build.flyme.version)$(getprop ro.flyme.published)$(getprop ro.build.version.opporom)$(getprop ro.vivo.os.version)$(getprop ro.build.version.emui)" ]; then
  { [ -n "$MI" ] || [ -n "$(getprop ro.miui.ui.version.code)" ] || [ -n "$(getprop ro.mi.os.version.code)" ]; } && hv "$OS" && SYSHY=1
fi
VHY=0; hv "$VND" && { [ -z "$ODM" ] || hv "$ODM"; } && VHY=1
[ $SYSHY = 1 ] && [ $VHY = 1 ] && BASE=
echo "${NAME:-未知机型}"; echo "${DEV:-unknown}"; echo "${OS:-未知系统}"; echo "$BASE"
