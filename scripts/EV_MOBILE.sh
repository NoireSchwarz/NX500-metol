#!/bin/bash
#=====================================================================
# EV_MOBILE.sh —— EV + WiFi → nxui 合并页 gui_evwifi.NX500
#=====================================================================
# 触发条件（keyscan 规则 A）：【按住 EV 键，再按 WiFi 键】
#   机型差异：WiFi 键 code 215 = nxkeyname "MOBILE"，NX500/NX1 通吃。
#
# ★ 2026-11-20 改写（本版）：
#   上一版（2026-10-18）= 本槽位直达 LUT 面板（`nxui.sh lut`），
#   FilmLab 独占 EV+AEL。现在 FilmLab 收进本页，EV+AEL 让给 V-Log。
#   页内条目：
#       FilmLab      → nxui.sh switch filmlab
#       LUT 滤镜     → nxui.sh switch lut
#       V-Log 曲线   → @gui_vlog.NX500
#       实用功能     → @gui_func.NX500
#       返回         → @gui_ini.NX500
#       取消         → nxui 自己关（gui_exit.sh 被 nxui 拦成 close_requested）
#
# ★ 为什么用 nxui 菜单而不是 mod_gui：
#   mod_gui 是三星原生 EFL 菜单，和 nxui 是两套渲染栈、两套焦点处理。
#   nxui 是我们自己的面板，菜单页与面板同一个二进制、同一套 .NX500 解析 ——
#   复用它是这套 mod 的核心优势，不该为了省事退回 EFL。
#
# ★ 面板之间怎么切：`nxui.sh switch <mode>`。
#   nxui 单实例，从菜单页 exec `nxui.sh lut` 会让 nxui.sh 的 pidof 命中
#   正在退出的自己 → killall 自杀 →「只杀不起」。switch 会先发 TERM、
#   轮询等旧进程真的消失，再起新的。
#
# 历史备份在机上：/opt/usr/nx-ks/nxui/backup-lut-20261018/EV_MOBILE.sh
#=====================================================================

D=/opt/usr/nx-ks
BB=$D/busybox

if [ -x "$D/nxui.sh" ] && "$D/nxui.sh" available; then
    "$D/nxui.sh" menu gui_evwifi.NX500
    exit $?
fi

# NXUI 不可用（未安装或已 disable）时给个提示，不再回退去起服务
if [ -x "$D/popup_timeout" ]; then
    nice -n +10 "$D/popup_timeout" " NXUI 未启用 " 3 >/dev/null 2>&1
fi
exit 1
