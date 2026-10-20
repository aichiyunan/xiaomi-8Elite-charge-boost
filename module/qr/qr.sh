#!/system/bin/sh
# 快充断流秒恢复：内置 mi_qc_retry.ko（kprobe 挂 mca_quick_charge_stop_charging，
# 停充后约 0.5 秒重放原厂事件 68，让原厂驱动自己重新判断进快充；不改电流/电压/保护阈值）
# 所有带原厂 MCA 快充模块（mca_strategy_quickchg）的机型可用；挂载点自检不过就不触发。ko 没有卸载函数：关闭 = enable=0，彻底移除需重启。
QD=${0%/*}; MD=${QD%/qr}
D=/data/adb/mi_charge_boost; mkdir -p $D
CONF=$D/qc_retry; LOG=$D/qr.log; P=/sys/module/mi_qc_retry/parameters
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; [ $(wc -l < $LOG) -gt 200 ] && sed -i '1,100d' $LOG; }
want(){ [ "$(cat $CONF 2>/dev/null)" = 1 ] && echo 1 || echo 0; }
avail(){ [ -d /sys/module/mca_strategy_quickchg ] && echo 1 || echo 0; }
pv(){ cat $P/$1 2>/dev/null || echo 0; }
load(){ # 未加载时 insmod；.loading 防死机循环（90 秒内没活下来，下次开机自动关闭开关）
  [ -d /sys/module/mi_qc_retry ] && return 0
  [ "$(avail)" = 1 ] || { log "本机不支持（未检测到原厂 MCA 快充模块）"; return 1; }
  echo 1 > $D/qr.loading; sync
  if insmod $QD/mi_qc_retry.ko enable=1 retry_ms=500 max_burst=6 2>>$LOG; then
    log "加载成功：$(dmesg | grep 'mi_qc_retry: armed' | tail -1 | sed 's/.*mi_qc_retry: //')"
    nohup sh -c "sleep 90; rm -f $D/qr.loading" >/dev/null 2>&1 &
    return 0
  fi
  rm -f $D/qr.loading; log "加载失败（内核版本不匹配或符号不存在），开关已关闭"; echo 0 > $CONF; return 1
}
apply(){
  if [ "$(want)" = 1 ]; then load && { echo 1 > $P/enable 2>/dev/null; log "${SRC:-手动} 已开启"; }
  else [ -d /sys/module/mi_qc_retry ] && echo 0 > $P/enable 2>/dev/null; log "${SRC:-手动} 已关闭"; fi
}
case "$1" in
  status) L=0; [ -d /sys/module/mi_qc_retry ] && L=1
    echo "{\"avail\":$(avail),\"want\":$(want),\"loaded\":$L,\"en\":$(pv enable),\"stops\":$(pv stops),\"replays\":$(pv replays),\"skipped\":$(pv skipped),\"mismatch\":$(pv mismatch)}";;
  set) [ "$2" = 1 ] && echo 1 > $CONF || echo 0 > $CONF; apply; sh $0 status;;
  boot) # service 调用：上次加载后死机则自动关闭
    if [ -f $D/qr.loading ]; then rm -f $D/qr.loading; echo 0 > $CONF; log "上次加载后系统未正常运行，已自动关闭"; exit 0; fi
    [ "$(want)" = 1 ] && SRC=开机 apply;;
  log) tail -n 30 $LOG 2>/dev/null || echo 暂无;;
  *) echo "用法: qr.sh status|set 0|1|boot|log";;
esac
