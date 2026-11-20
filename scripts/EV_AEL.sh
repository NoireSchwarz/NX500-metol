#!/bin/bash
#=====================================================================
# EV_AEL.sh —— EV + AEL → V-Log 曲线（nxui 菜单页 gui_vlog.NX500）
#=====================================================================
# ★ 2026-11-20 换绑：本槽位原为 FilmLab 配方菜单（mod_gui 三层页）。
#   FilmLab 已并入 EV+WiFi 的 nxui 合并页，本槽位腾给 V-Log 曲线 ——
#   一组键一个功能，不再为 V-Log 另开组合键。
#
# ★ 触发条件（keyscan 规则 A）：【按住 EV 键，再按 AEL 键】
#   keyscan.c: if (ev_pressed == 1 && code != NXKEY_EV && value == 1)
#                  sprintf(shell_name, "EV_%s", nxkeyname[code]);
#   ⇒ 文件名必须恰好是 EV_AEL.sh（AEL 有 nxkeyname 表项）。
#
# ★ 为什么走 nxui 菜单而不是再写一个面板：
#   面板（nxui.arm）是单实例，一个模式一件事；而 V-Log 只有四个动作
#   （开关 / 回原厂 / 状态 / 放行检查），做成菜单页最省。菜单页和面板
#   是同一个二进制、同一套 .NX500 解析，不存在第二套 UI 栈。
#
# ★ 历史（别被上面的注释误导）：
#   2026-10-08 起本槽位走 mod_gui，原因是当时自绘全屏 EFL 窗口会在单核
#   NX500 上把整机拖死。那是 EFL 的问题，不是 nxui 的问题 —— nxui 是
#   X11 + Nuklear 自绘，720×208 实测流畅，早已取代 mod_gui 成为主 UI。
#   原社区脚本备份仍在 /opt/usr/nx-ks/EV_AEL.community.sh。
#=====================================================================
BB=/opt/usr/nx-ks/busybox
D=/opt/usr/nx-ks

# ---- 机型闸门：V-Log 引擎与 PW/A18 判据只在 NX500 1.12 实证过 ----
if ! /bin/grep -q '^NX500$' /etc/version.info; then
    [ -x "$D/EV_AEL.community.sh" ] && exec "$D/EV_AEL.community.sh" "$@"
    exit 0
fi

# ---- 主路径：nxui 菜单页（同槽再按一次即关，由 nxui.sh 的 toggle 负责）----
if [ -x "$D/nxui.sh" ] && "$D/nxui.sh" available; then
    "$D/nxui.sh" vlog
    exit $?
fi

# ---- NXUI 不可用：不再回退 mod_gui，直接说清楚 ----
if [ -x "$D/popup_timeout" ]; then
    nice -n +10 "$D/popup_timeout" " V-Log: NXUI 未启用 " 3 >/dev/null 2>&1
fi
exit 1
