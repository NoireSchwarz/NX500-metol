#!/bin/sh
# ap-reset.sh —— 把 di-camera-app 的 AP 状态字复位到 0
#
# 背景（2026-11-22）：nxl-wifi-radio 的 baseline() 只接受 ap_state==0，
# 本机 `st app softap stop` 之后该字停在 10。复位办法是让原厂完整走一次
# 「起 2.4G AP → 就绪 → 停」，状态机会自己回到 0。
#
# 会断开 mlan0 的 STA 连接（起 AP 期间），所以由调用方 setsid 分离执行。
# 日志：/mnt/mmc/nx-ks/ap-reset.log
ST=/usr/bin/st
LOG=/mnt/mmc/nx-ks/ap-reset.log
SRV=/opt/usr/nx-lut-lite/bin/nxl-wifi-server

uap_ip() {
  ifconfig uap0 2>/dev/null | awk '/inet addr/{sub("addr:","",$2);print $2;exit}'
}

{
  printf '=== %s ap-reset begin ===\n' "$(date)"
  "$ST" app softap start 2>&1
  printf 'start rc=%s\n' "$?"

  i=0
  ip=
  while [ "$i" -lt 60 ]; do
    ip=$(uap_ip)
    [ -n "$ip" ] && break
    sleep 1
    i=$((i+1))
  done
  printf 'uap0 ip=%s after %ss\n' "${ip:-none}" "$i"

  # 给它两秒把 state 推到就绪
  sleep 2
  if [ -x "$SRV" ]; then
    "$SRV" --status 2>&1 | sed -n 's/^\(ap_valid\|ap_state\|owned\|mode\)=/AFTER_START \1=/p'
  fi

  "$ST" app softap stop 2>&1
  printf 'stop rc=%s\n' "$?"

  i=0
  while [ "$i" -lt 60 ]; do
    ip=$(uap_ip)
    [ -z "$ip" ] && break
    sleep 1
    i=$((i+1))
  done
  printf 'uap0 gone after %ss\n' "$i"

  sleep 2
  if [ -x "$SRV" ]; then
    "$SRV" --status 2>&1 | sed -n 's/^\(ap_valid\|ap_state\|owned\|mode\|ip\)=/AFTER_STOP \1=/p'
  fi
  printf '=== %s ap-reset done ===\n' "$(date)"
} >>"$LOG" 2>&1
