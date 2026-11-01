#!/system/bin/sh
# WebUI：输出本机型参数 JSON
MCB_ROOT=${0%/*}; . $MCB_ROOT/models.sh
C=$(model_code); model_load "$C"
p=""; for x in $PWO; do p="$p${p:+,}$x"; done
# 本机原厂满充截止电压（v8.6.4）：从原厂备份/当前 dtbo 读，读不到用表内值
F0=$(sh $MCB_ROOT/dtbo/apply.sh fvq 2>/dev/null); case "$F0" in 4[4-7][0-9][0-9]) ;; *) F0=$VQ;; esac
echo "{\"ok\":1,\"code\":\"$C\",\"name\":\"$MN\",\"modname\":\"$MODNAME\",\"imin\":9000,\"imax\":$MX,\"istock\":$MI,\"vq\":$VQ,\"v0\":$V0,\"pw0\":$PW0,\"pwo\":[$p],\"hz\":$HZ,\"fv0\":${F0:-0},\"gen\":${GEN:-0}}"
