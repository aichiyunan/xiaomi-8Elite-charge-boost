#!/system/bin/sh
# 输出四行：机型名 / 机型代号 / 系统 / 底包（vendor 固件版本，dtbo 跟它走）
# 兼容移植系统（ColorOS 等）：ro.product.* 可能被改成别家，优先读 vendor/odm 分区
g(){ for p; do v=$(getprop $p); [ -n "$v" ] && { echo "$v"; return; }; done; }
NAME=$(g ro.product.marketname ro.product.vendor.marketname ro.product.odm.marketname ro.vendor.oplus.market.name ro.product.vendor.model ro.product.model)
DEV=$(g ro.product.vendor.device ro.product.odm.device ro.product.device)
# 已适配机型（dada / haotian / miro / annibale / warsaw）：任一 device 属性是已适配代号就以它为准，vendor/odm 优先（dtbo 跟底包走）
SUP=" dada haotian miro annibale warsaw "
case "$SUP" in *" $DEV "*) ;; *) for p in ro.product.vendor.device ro.product.odm.device ro.product.device ro.product.system.device; do v=$(getprop $p); case "$SUP" in *" $v "*) DEV=$v; break;; esac; done;; esac
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
[ "$BASE" = "$OS" ] && BASE=
# 原版 HyperOS/MIUI 不显示底包，只有移植系统才显示
[ -z "$OPL" ] && case "$OS" in OS*|V*) BASE=;; esac
echo "${NAME:-未知机型}"; echo "${DEV:-unknown}"; echo "${OS:-未知系统}"; echo "$BASE"
