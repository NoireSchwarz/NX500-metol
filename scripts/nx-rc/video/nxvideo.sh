#!/bin/sh
# @gate  opens=none one_shot=0 gate=none pconly=0
#=====================================================================
# nxvideo.sh — 视频档位切换（全宽 UHD24 / UHD / 2.5K / crop80）
#=====================================================================
# 来源：NoireSchwarz RC6.14.10 的 video-mode.sh（AGPL-3.0）。
# 二进制逐字节与 RC6.14.10 相同（SHA 已核），本脚本只重写壳：
#   · 用 busybox sha256sum 做组件校验（不用对方的 nxl-fileops 自校验）
#   · 加了统一的日志与中文状态行
#   · 步骤序列与对方完全一致，不改顺序（顺序是实测出来的，改了就没有因果保证）
#
# 用法：
#   nxvideo.sh status     当前档位（只读）
#   nxvideo.sh full       全宽 UHD 24p（native_reload video24 → uhd → apply → 24p）
#   nxvideo.sh uhd        原生 UHD 30p（恢复原厂输出映射 + rate70）
#   nxvideo.sh 2k         2.5K 输出
#   nxvideo.sh crop80     裁切 80% + 30p
#   nxvideo.sh usb-check  只看 USB 守卫状态
#
# 退出码：0 成功 / 1 组件校验失败或步骤失败 / 2 用法错
#=====================================================================
set -u
D=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOME_DIR=${NXVIDEO_HOME:-$D}
BB=$D/busybox
[ -x "$BB" ] || BB=/opt/usr/nx-ks/busybox
[ -x "$BB" ] || BB=/mnt/mmc/busybox
LOG=/mnt/mmc/nx-ks/video.log
mkdir -p /mnt/mmc/nx-ks 2>/dev/null

# 组件（SHA256 与 RC6.14.10 固定）
OPS_SHA=c5ab4fad18a3908f2c90058665b158c925267d88dd9c2e01c349fa9b149d759d
MODE_SHA=690c4c409b6684679a747ca84a3c26e8c8c44cf4c4212b9c2a9e7810b2b4b2f1
FULL_SHA=4839e68c0b96fb0a627259e5c74da047e9e44dea183108ad805b17e80d81ea2c
USB_SHA=61bf59b3bf4ccba775525e40024d0a42b86cffd22a1b94d9a431a8102f266918
REFRESH_SHA=3a7b272e3be9ad81996c823f17f33d84e990a85eff0f252785db7d575a0ceac7

OPS=$HOME_DIR/bin/nxl-fileops
MODE=$HOME_DIR/bin/nxl-video-mode.arm
FULL=$HOME_DIR/bin/nxl-video-fullwidth.arm
REFRESH=$HOME_DIR/bin/nxl-native-refresh.arm
USB=$HOME_DIR/bin/nxl-usb-guard.arm

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null; }
say() { printf '%s\n' "$*"; }
bad() { say "VIDEO_COMPONENT_IDENTITY_FAILED $1"; log "identity fail $1"; exit 1; }

sha_of() {
  # 输出文件 sha256 小写；失败输出空
  "$BB" sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

check() {
  f=$1; want=$2; name=$3
  [ -f "$f" ] || bad "$name missing: $f"
  [ -L "$f" ] && bad "$name is symlink: $f"
  [ -x "$f" ] || bad "$name not executable: $f"
  got=$(sha_of "$f")
  [ "$got" = "$want" ] || bad "$name sha mismatch: got=$got"
  return 0
}

identify() {
  check "$OPS" "$OPS_SHA" nxl-fileops
  check "$MODE" "$MODE_SHA" nxl-video-mode
  check "$FULL" "$FULL_SHA" nxl-video-fullwidth
  check "$USB" "$USB_SHA" nxl-usb-guard
  return 0
}

usb_check() {
  # $1 = 阶段名。USB 守卫拒绝时打印状态并返回非 0
  out=$("$USB" preflight "$1" 2>&1)
  rc=$?
  [ "$rc" = 0 ] && return 0
  reason=USB_CONFIG_GUARD_FAILED
  for line in $out; do
    case "$line" in
      reason=*) reason=${line#reason=} ;;
    esac
  done
  case "$reason" in
    ''|*[!A-Z0-9_]*) reason=USB_CONFIG_GUARD_FAILED ;;
  esac
  say "VIDEO_USB_BLOCKED reason=$reason"
  say "state=UNKNOWN width=0 height=0 reason=$reason"
  log "usb blocked at $1 reason=$reason"
  return 1
}

native_reload() {
  check "$REFRESH" "$REFRESH_SHA" nxl-native-refresh
  mkdir -p /tmp/nx-ks-video 2>/dev/null
  if "$REFRESH" "$1" >/tmp/nx-ks-video/refresh.log 2>&1; then
    log "native_reload $1 ok"
    return 0
  fi
  say "VIDEO_NATIVE_RELOAD_UNCONFIRMED profile=$1"
  say "state=UNKNOWN width=0 height=0 reason=VIDEO_NATIVE_RELOAD_UNCONFIRMED"
  log "native_reload $1 FAILED"
  return 1
}

step() {
  # $1 = 阶段名，其余 = 命令
  phase=$1; shift
  out=$("$@" 2>&1); rc=$?
  usb_check "$phase" || return 1
  if [ "$rc" != 0 ]; then
    say "$out"
    log "step $phase rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
    return 1
  fi
  log "step $phase ok"
  return 0
}

MODE_ARG=${1:-}
case "$MODE_ARG" in
  status)
    identify
    usb_check STATUS || exit 1
    "$FULL" status
    exit $?
    ;;
  usb-check)
    identify
    "$USB" check STARTUP
    exit $?
    ;;
  full|uhd|2k|crop80) : ;;
  *)
    say "usage: nxvideo.sh status|full|uhd|2k|crop80|usb-check"
    exit 2
    ;;
esac

identify
usb_check BEFORE_VIDEO || exit 1

case "$MODE_ARG" in
  full)
    native_reload video24 || exit 1
    step BEFORE_NATIVE24_SELECTION "$MODE" check24p || exit 1
    step AFTER_UHD_MAPPING "$MODE" uhd || exit 1
    step AFTER_FULLWIDTH "$FULL" apply || exit 1
    step AFTER_NATIVE24_MAPPING "$MODE" 24p || exit 1
    native_reload video24 || exit 1
    step AFTER_NATIVE24_STATUS "$FULL" status || exit 1
    ;;
  crop80)
    native_reload video30 || exit 1
    step AFTER_DCI_RESTORE "$MODE" dci-native || exit 1
    step AFTER_RESTORE "$FULL" restore || exit 1
    step AFTER_OUTPUT_MAPPING "$MODE" uhd || exit 1
    step AFTER_RATE_PATCH "$MODE" 30p || exit 1
    native_reload video30 || exit 1
    ;;
  2k|uhd)
    native_reload video30 || exit 1
    step AFTER_DCI_RESTORE "$MODE" dci-native || exit 1
    step AFTER_RESTORE "$FULL" restore || exit 1
    step AFTER_OUTPUT_MAPPING "$MODE" "$MODE_ARG" || exit 1
    if [ "$MODE_ARG" = uhd ]; then
      step AFTER_RATE_RESTORE "$MODE" rate70 || exit 1
    fi
    native_reload video30 || exit 1
    ;;
esac

say "$out"
log "done $MODE_ARG"
exit 0
