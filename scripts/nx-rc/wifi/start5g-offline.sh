#!/bin/sh
# start5g-offline.sh —— 离线起 5 GHz 热点
#
# 背景（2026-11-22）：nxl-wifi-radio 的 radio_baseline() 要求
#   mlan0 接口存在(sta==1) 且「没有取到 IP」，否则报 STATION_CONNECTION_PRESENT。
# 而 SSH 正是走 mlan0 的 IP —— 所以必须在机端分离执行：
#   断开 STA 关联 → 清掉 mlan0 的 IP（接口保持 up）→ 跑 start5g → 失败则重连。
#
# 调用方必须 setsid 分离，否则 SSH 断开时脚本会被 SIGHUP 杀掉：
#   setsid sh ./start5g-offline.sh </dev/null >/dev/null 2>&1 &
# 日志：/mnt/mmc/nx-ks/5g-offline.log
WPA=/usr/sbin/wpa_cli
LOG=/mnt/mmc/nx-ks/5g-offline.log
NXWIFI=/opt/usr/nx-ks/nx-rc/wifi/nxwifi.sh

mlan_ip() {
  ifconfig mlan0 2>/dev/null | awk '/inet addr/{sub("addr:","",$2);print $2;exit}'
}

{
  printf '=== %s offline-5g begin ===\n' "$(date)"
  printf 'before: mlan0 ip=%s\n' "$(mlan_ip)"

  "$WPA" -i mlan0 disconnect 2>&1
  printf 'disconnect rc=%s\n' "$?"

  # 清 IP 但保持接口 up：radio 要求 sta==1 且无 IP。
  # busybox ifconfig 不吃 "0.0.0.0"，只支持 del ADDRESS[/PREFIXLEN]（2026-11-22 实测）。
  ip=$(mlan_ip)
  if [ -n "$ip" ]; then
    ifconfig mlan0 del "$ip" 2>&1
    printf 'del-ip(%s) rc=%s\n' "$ip" "$?"
    sleep 1
    ip=$(mlan_ip)
    if [ -n "$ip" ]; then
      ifconfig mlan0 del "$ip/24" 2>&1
      printf 'del-ip(%s/24) rc=%s\n' "$ip" "$?"
    fi
  fi

  i=0
  while [ "$i" -lt 10 ]; do
    ip=$(mlan_ip)
    [ -z "$ip" ] && break
    sleep 1
    i=$((i+1))
  done
  printf 'after: mlan0 ip=%s (%ss)\n' "${ip:-none}" "$i"

  out=$(sh "$NXWIFI" start5g 2>&1)
  rc=$?
  printf '%s\n' "$out"
  printf 'start5g rc=%s\n' "$rc"

  if [ "$rc" -ne 0 ]; then
    printf 'restoring STA\n'
    "$WPA" -i mlan0 reconnect 2>&1
    printf 'reconnect rc=%s\n' "$?"
    sleep 3
    printf 'restored: mlan0 ip=%s\n' "$(mlan_ip)"
  else
    printf 'hotspot up, leaving STA down\n'
  fi
  printf '=== %s offline-5g done ===\n' "$(date)"
} >>"$LOG" 2>&1
