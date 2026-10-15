#!/system/bin/sh
# 高刷守护：开机恢复上次档位；亮屏每 5 秒刷新状态缓存；超频档被熄屏/系统打断后逐级拉回
MODDIR=${0%/*}; MODDIR=${MODDIR%/hz}
. $MODDIR/hz/common.sh
rmdir $LOCK 2>/dev/null; rm -f $FAILF $AVAILF
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 20
[ -n "$(get_id 165)" ] && echo 1 > $AVAILF || echo 0 > $AVAILF
HZ=$(cat $CONF 2>/dev/null); [ -z "$HZ" ] && HZ=120
if [ "$HZ" -gt 120 ] && [ "$(cat $AVAILF)" = 0 ]; then
  hist "当前 dtbo 无超频档位，${HZ}Hz 未恢复"; echo 120 > $CONF; HZ=120
fi
[ "$HZ" -gt 120 ] && [ ! -f $OFFF ] && SRC=开机 apply_hz $HZ >/dev/null 2>&1
write_stat
while true; do
  sleep 5
  timeout 4 dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake" || continue
  [ -d $LOCK ] && continue
  write_stat
  [ -f $MODDIR/disable ] && continue
  [ -f $OFFF ] && continue
  T=$(cat $CONF 2>/dev/null); [ -z "$T" ] && T=120
  [ "$T" -le 120 ] && continue
  [ -f $FAILF ] && continue
  read C W I < $STATF
  [ "$C" = "$T" ] || { hist "检测到掉档 ${C}Hz，自动拉回"; SRC=守护 apply_hz $T >/dev/null 2>&1; write_stat; }
done
