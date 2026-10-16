#!/system/bin/sh
# WebUI：输出本机型参数 JSON
MCB_ROOT=${0%/*}; . $MCB_ROOT/models.sh
C=$(model_code); model_info "$C" || { echo '{"code":"'$C'","ok":0}'; exit 0; }
p=""; for x in $PWO; do p="$p${p:+,}$x"; done
echo "{\"ok\":1,\"code\":\"$C\",\"name\":\"$MN\",\"modname\":\"$MODNAME\",\"imin\":9000,\"imax\":$MX,\"istock\":$MI,\"vq\":$VQ,\"v0\":$V0,\"pw0\":$PW0,\"pwo\":[$p],\"hz\":$HZ}"
