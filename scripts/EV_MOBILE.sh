#!/bin/bash
#=====================================================================
# EV_MOBILE.sh —— EV + WiFi → nxui 合并页 gui_evwifi.NX500
#=====================================================================
# 触发条件（keyscan 规则 A）：【按住 EV 键，再按 WiFi 键】
#   机型差异：WiFi 键 code 215 = nxkeyname "MOBILE"，NX500/NX1 通吃。
#
# ★ 2026-11-20 改写（方案 2b）：本槽位是滤镜功能的**唯一入口**。
#   历史：2026-10-18 本槽位直达 LUT 面板（`nxui.sh lut`），FilmLab 独占
#   EV+AEL，V-Log 另想一组键 —— 三组组合键换三个入口不划算。
#   现在 FilmLab 与 LUT 是同一面板的两个页签（进程内换层），V-Log 也在本页里，
#   EV+AEL 已腾空回社区原版。
#   页内条目：
#       LUT 滤镜     → filter:lut   （nxui 进程内换到 LUT 层）
#       FilmLab      → filter:pw    （换到 PW 层）
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
# ★ 为什么不再用 `nxui.sh switch <mode>`：
#   那条路要杀掉自己再起一个进程（1 秒黑屏），而且 nxui.sh 的 pidof 会命中
#   正在退出的自己 →「只杀不起」。现在换层只是换列表，进程/窗口/焦点都不动。
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
