#!/bin/sh
# @gate  opens=none one_shot=0 gate=none pconly=0
#=====================================================================
# nxwifi.sh — SoftAP 相簿壳（2.4 GHz），迁移自 NoireSchwarz RC6.14.10 契约
#=====================================================================
# 设计（2026-11-22）：
#   · 只做「起壳 + 状态 + 停壳」三件事，不接管 web 服务
#     web 相册仍由 thumb-cgi / nx-rc 那条链提供（80 端口）
#   · 起壳方式与原厂一致：/usr/bin/st app softap start —— 不替换网络守护进程，
#     不写任何相机内存（对方 hot_start() 的同一条原厂入口）
#   · 5 GHz 版本需要三重条件（band word + cfg80211-cn-low5g.ko + 起壳），
#     本脚本暂不实现，start5g 明确返回 NOT_IMPLEMENTED
#   · 热点密码无法从用户态配置读出（原厂存在 di-camera-app 的 preference 页），
#     本脚本只报 SSID + uap0 地址；密码提示用机身「移动 AP」设置里的那个
#
# 用法：
#   nxwifi.sh album        局域网相册地址（相机连路由器时用这条，屏幕弹提示）
#   nxwifi.sh off          断开 WiFi（相机离线）
#   nxwifi.sh start24      起 2.4 GHz 热点（原厂 SoftAP，本机原厂入口不可用，保留）
#   nxwifi.sh start5g      起 5 GHz 热点（需 radio，当前卡在原厂 tethering 未激活）
#   nxwifi.sh stop         停热点
#   nxwifi.sh status       状态：state / ip / ssid
#
# 退出码：0 成功 / 1 前置条件不满足 / 2 用法错 / 3 起壳失败 / 4 停壳失败
#=====================================================================
set -u
D=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${NXWIFI_ROOT:-/opt/usr/nx-ks}
BB=$D/busybox
[ -x "$BB" ] || BB=/opt/usr/nx-ks/busybox
[ -x "$BB" ] || BB=/mnt/mmc/busybox
ST=/usr/bin/st
SRV=$D/bin/nxl-wifi-server
RADIO=$D/bin/nxl-wifi-radio
MOD=$D/modules/cfg80211-cn-low5g.ko
# nxl-wifi-radio 里 INSTALLED 是编译期常量 /opt/usr/nx-lut-lite，必须真实存在
NXL_DIR=/opt/usr/nx-lut-lite
POPUP=/opt/usr/nx-ks/popup_timeout
HOT_OWNER=/tmp/nx-lut-lite/wifi-hotspot.owner
LOG=/mnt/mmc/nx-ks/wifi.log
mkdir -p /mnt/mmc/nx-ks 2>/dev/null
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null; }
say() { printf '%s\n' "$*"; }
die() { say "$1"; log "FAIL $1"; exit "${2:-1}"; }

sha_of() {
  "$BB" sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

ensure_nxl_layout() {
  # radio 的 INSTALLED 是编译期常量，只能在 /opt/usr/nx-lut-lite 下找组件
  mkdir -p "$NXL_DIR/bin" "$NXL_DIR/wireless" 2>/dev/null || return 1
  if [ ! -f "$NXL_DIR/bin/nxl-wifi-server" ] || [ "$(sha_of "$SRV")" != "$(sha_of "$NXL_DIR/bin/nxl-wifi-server")" ]; then
    cp "$SRV" "$NXL_DIR/bin/nxl-wifi-server" && chmod 755 "$NXL_DIR/bin/nxl-wifi-server" || return 1
  fi
  if [ ! -f "$NXL_DIR/bin/nxl-wifi-radio" ] || [ "$(sha_of "$RADIO")" != "$(sha_of "$NXL_DIR/bin/nxl-wifi-radio")" ]; then
    cp "$RADIO" "$NXL_DIR/bin/nxl-wifi-radio" && chmod 755 "$NXL_DIR/bin/nxl-wifi-radio" || return 1
  fi
  if [ ! -f "$NXL_DIR/wireless/cfg80211-cn-low5g.ko" ] || [ "$(sha_of "$MOD")" != "$(sha_of "$NXL_DIR/wireless/cfg80211-cn-low5g.ko")" ]; then
    cp "$MOD" "$NXL_DIR/wireless/cfg80211-cn-low5g.ko" && chmod 644 "$NXL_DIR/wireless/cfg80211-cn-low5g.ko" || return 1
  fi
  return 0
}

mlan_ip() {
  # 相机作为 STA 连在路由器上的地址（局域网相册用这一条）
  ifconfig mlan0 2>/dev/null | awk '/inet addr/{sub("addr:","",$2);print $2;exit}'
}

uap_ip() {
  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig uap0 2>/dev/null | awk '/inet addr/{sub("addr:","",$2);print $2;exit}'
  else
    ip -4 addr show uap0 2>/dev/null | awk '/inet /{sub("/.*","",$2);print $2;exit}'
  fi
}

uap_ssid() {
  iwconfig uap0 2>/dev/null | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p' | head -1
}

usb_state() {
  cat /sys/class/extcon/USB/state 2>/dev/null || echo unknown
}

recording() {
  # 我方 P0 判据：di-camera-app 持有写打开的 MP4 fd 即视为在录
  pid=$(pidof di-camera-app 2>/dev/null | awk '{print $1}')
  [ -n "$pid" ] || return 1
  for p in /proc/"$pid"/fd/*; do
    [ -e "$p" ] || continue
    case "$(readlink "$p" 2>/dev/null)" in
      *.MP4*) return 0 ;;
    esac
  done
  return 1
}

preflight() {
  s=$(usb_state)
  case "$s" in
    0|"") : ;;
    *) die "USB_CONNECTED_DISCONNECT_FIRST (state=$s)" 1 ;;
  esac
  if recording; then die "RECORDING_ACTIVE_REFUSE" 1; fi
  [ -x "$ST" ] || die "ST_MISSING $ST" 1
  return 0
}

# 热点起来后没人知道该连哪儿 —— 屏幕上弹一次地址，手机照着敲/扫。
# ★ 原厂 mobileap-agent 没跑时，hostapd 永远不会被调起 ⇒ 热点起不来（2026-11-22 实证）。
#   它由 system bus 上的 org.tizen.tethering 激活：服务定义在
#   /usr/share/dbus-1/services/，而 /etc/dbus-1/system.conf 的 <servicedir> 正指向那里。
#   所以「发一条 Ping」就能把它拉起来 —— 任何方法调用都会触发 dbus 激活。
ensure_tethering() {
  if ps 2>/dev/null | grep -q "[m]obileap-agent"; then
    log "tethering already running"
    return 0
  fi
  [ -x /usr/bin/dbus-send ] || return 1
  log "tethering not running, activating org.tizen.tethering"
  /usr/bin/dbus-send --system --print-reply --dest=org.tizen.tethering \
      / org.freedesktop.DBus.Peer.Ping >>"$LOG" 2>&1
  i=0
  while [ "$i" -lt 20 ]; do
    ps 2>/dev/null | grep -q "[m]obileap-agent" && { log "tethering activated"; return 0; }
    sleep 0.5
    i=$((i+1))
  done
  log "tethering activation FAILED"
  return 1
}

hotspot_notice() {
  label=$1
  hip=$(uap_ip)
  if [ -z "$hip" ] && [ -n "${SRV:-}" ] && [ -x "$SRV" ]; then
    hip=$("$SRV" --status 2>/dev/null | sed -n 's/^ip=//p' | head -1)
  fi
  if [ -z "$hip" ]; then
    say "HOTSPOT_UP_NO_IP $label（热点已起但 uap0 暂无地址，等几秒再点一次相册地址）"
    log "hotspot up $label but no uap0 ip"
    return 0
  fi
  say "HOTSPOT_UP $label url=http://$hip/"
  log "hotspot up $label url=http://$hip/"
  if [ -x "$POPUP" ]; then
    "$POPUP" " [ http://$hip/ ] " 10 2>/dev/null &
  fi
  return 0
}

case "${1:-status}" in
  start24)
    preflight
    ensure_tethering || log "start24: tethering not activated, hotspot may fail"
    ip=$(uap_ip)
    if [ -n "$ip" ]; then
      say "ALREADY_UP ip=$ip ssid=$(uap_ssid)"
      log "start24 already up ip=$ip"
      exit 0
    fi
    log "start24 begin"
    if [ -x "$SRV" ]; then
      # 首选：对方的静态二进制，自带 SSID/密码读取与 2.4G 频段确认
      out=$("$SRV" --hotspot-start-24 2>&1)
      rc=$?
      printf '%s\n' "$out" >>"$LOG"
      case "$out" in
        *connected=1*) say "$out"; hotspot_notice "2.4GHz"; exit 0 ;;
      esac
      say "$out"
      log "start24 server rc=$rc"
      exit 3
    fi
    # 回退：只用原厂 st 起壳，读不到密码
    "$ST" app softap start >>"$LOG" 2>&1
    rc=$?
    i=0
    while [ "$i" -lt 100 ]; do
      ip=$(uap_ip)
      [ -n "$ip" ] && break
      sleep 0.2
      i=$((i+1))
    done
    if [ -n "$ip" ]; then
      say "HOTSPOT_UP ip=$ip ssid=$(uap_ssid) password=UNKNOWN(st-fallback)"
      log "start24 up (fallback) ip=$ip st_rc=$rc"
      [ -x "$POPUP" ] && "$POPUP" " [ http://$ip/ ] " 10 2>/dev/null &
      exit 0
    fi
    say "HOTSPOT_START_PENDING st_rc=$rc (无 uap0 地址，原厂可能仍在启动或机身设置里未启用移动 AP)"
    log "start24 pending st_rc=$rc"
    exit 3
    ;;
  stop)
    # 先退射频（还原 band word / 卸载 RAM 模块），再停 web 与热点
    if [ -x "$NXL_DIR/bin/nxl-wifi-radio" ]; then
      "$NXL_DIR/bin/nxl-wifi-radio" --stop >>"$LOG" 2>&1
      log "stop radio rc=$?"
    elif [ -x "$RADIO" ]; then
      "$RADIO" --stop >>"$LOG" 2>&1
      log "stop radio(fallback) rc=$?"
    fi
    if [ -x "$SRV" ]; then
      "$SRV" --stop >>"$LOG" 2>&1
      say "HOTSPOT_DOWN (server --stop rc=$?)"
      exit 0
    fi
    preflight
    ip=$(uap_ip)
    if [ -z "$ip" ]; then
      say "ALREADY_DOWN"
      exit 0
    fi
    log "stop begin ip=$ip"
    "$ST" app softap stop >>"$LOG" 2>&1
    rc=$?
    i=0
    while [ "$i" -lt 50 ]; do
      [ -z "$(uap_ip)" ] && break
      sleep 0.2
      i=$((i+1))
    done
    if [ -z "$(uap_ip)" ]; then
      say "HOTSPOT_DOWN"
      log "stop down st_rc=$rc"
      exit 0
    fi
    say "HOTSPOT_STOP_PENDING st_rc=$rc"
    log "stop pending st_rc=$rc"
    exit 4
    ;;
  status)
    if [ -x "$SRV" ]; then
      "$SRV" --status
      exit $?
    fi
    ip=$(uap_ip)
    ssid=$(uap_ssid)
    usb=$(usb_state)
    if [ -n "$ip" ]; then
      say "state=up ip=$ip ssid=${ssid:-unknown} usb=$usb"
    else
      say "state=down ssid=${ssid:-none} usb=$usb"
    fi
    ;;
  album)
    # 局域网相册：不启热点，只用相机当前的 STA 地址。手机/PC 连同一路由器即可访问。
    ip=$(mlan_ip)
    if [ -z "$ip" ]; then
      say "WIFI_DOWN 相机未连 WiFi"
      log "album: no mlan0 ip"
      [ -x "$POPUP" ] && "$POPUP" " [ 未连 WiFi ] " 3 2>/dev/null &
      exit 1
    fi
    say "ALBUM http://$ip/"
    log "album url=http://$ip/"
    if [ -x "$POPUP" ]; then
      "$POPUP" " [ http://$ip/ ] " 5 2>/dev/null &
    fi
    exit 0
    ;;
  off)
    # 断开 STA（相机离线）。恢复靠机身 WiFi 键或下次开机。
    ip=$(mlan_ip)
    if [ -z "$ip" ]; then
      say "ALREADY_OFF"
      exit 0
    fi
    log "off begin ip=$ip"
    /usr/sbin/wpa_cli -i mlan0 disconnect >/dev/null 2>&1
    ifconfig mlan0 del "$ip" >/dev/null 2>&1
    rm -f "$HOT_OWNER" 2>/dev/null
    say "WIFI_OFF"
    exit 0
    ;;
  start5g)
    preflight
    [ -x "$RADIO" ] || die "RADIO_MISSING $RADIO" 1
    ensure_nxl_layout || die "NXL_LAYOUT_FAILED $NXL_DIR" 1
    ensure_tethering || log "start5g: tethering not activated, hotspot may fail"
    # ★ radio 用 live_identity() 比对 /proc/<pid>/exe == /opt/usr/nx-lut-lite/bin/nxl-wifi-radio。
    #   从 $D 调起来 exe 是另一个路径，守护进程会判定 AP_LEASE_LOST（2026-11-22 实测）。
    SRV=$NXL_DIR/bin/nxl-wifi-server
    RADIO=$NXL_DIR/bin/nxl-wifi-radio
    hip=$(uap_ip)
    [ -n "$hip" ] && die "HOTSPOT_ALREADY_UP ip=$hip 先 nxwifi.sh stop" 1
    # ★ radio_baseline() 要求 mlan0「存在但无 IP」：
    #   interface_present() 只查 /sys/class/net/mlan0，`down` 之后目录仍在 ⇒ 仍算 present；
    #   down 的接口没有 IP（2026-11-22 实测：down 后 inet addr 消失、sysfs 仍在）。
    #   ⚠ 这是竞争条件：connmand 会在数秒内把接口 up 回来并重新 DHCP，
    #   所以 down 之后不等、不判死，直接把控制权交给 radio，由它自己报真实原因。
    sta=$(mlan_ip)
    if [ -n "$sta" ]; then
      log "start5g: bringing mlan0 down (was $sta)"
      /usr/sbin/wpa_cli -i mlan0 disconnect >>"$LOG" 2>&1
      ifconfig mlan0 down >>"$LOG" 2>&1
      sleep 1
      log "start5g: mlan0 down, ip now $(mlan_ip)"
    fi
    log "start5g begin (CH48 / 5240 MHz / HT40-minus)"
    "$SRV" --web-stop >>"$LOG" 2>&1
    if ! "$RADIO" --prepare >>"$LOG" 2>&1; then
      "$SRV" --stop >>"$LOG" 2>&1
      [ -n "$sta" ] && { ifconfig mlan0 up; /usr/sbin/wpa_cli -i mlan0 reconnect; } >>"$LOG" 2>&1
      die "RADIO_PREPARE_FAILED 见 $LOG（band word 或 cfg80211-cn-low5g.ko 未就绪）" 3
    fi
    if ! out=$("$SRV" --hotspot-start 2>&1); then
      "$RADIO" --stop >>"$LOG" 2>&1
      say "$out"
      log "start5g hotspot failed"
      [ -n "$sta" ] && { ifconfig mlan0 up; /usr/sbin/wpa_cli -i mlan0 reconnect; } >>"$LOG" 2>&1
      exit 3
    fi
    if ! "$RADIO" --confirm-profile >>"$LOG" 2>&1; then
      "$RADIO" --stop >>"$LOG" 2>&1
      "$SRV" --stop >>"$LOG" 2>&1
      [ -n "$sta" ] && { ifconfig mlan0 up; /usr/sbin/wpa_cli -i mlan0 reconnect; } >>"$LOG" 2>&1
      die "RADIO_PROFILE_UNCONFIRMED（期望 uap0 = 5240 MHz）" 3
    fi
    say "$out"
    log "start5g ok"
    hotspot_notice "5GHz"
    exit 0
    ;;
  *)
    say "usage: nxwifi.sh start24|stop|status|start5g"
    exit 2
    ;;
esac
