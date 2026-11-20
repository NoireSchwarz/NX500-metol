#!/bin/bash
#=====================================================================
# EV_MOBILE.sh —— EV + WiFi → 打开合并页 gui_evwifi.NX500
#=====================================================================
# 触发条件（keyscan 规则 A）：【按住 EV 键，再按 WiFi 键】
#   机型差异：WiFi 键 code 215 = nxkeyname "MOBILE"，NX500/NX1 通吃。
#
# ★ 2026-11-20 改写（本版）：
#   上一版（2026-10-18）= 本槽位直达 LUT 面板（`nxui.sh lut`），
#   FilmLab 则独占 EV+AEL。V-Log 曲线接进来还想再要一组组合键 ——
#   三组键换三个入口不划算。⇒ 改成打开一页，页里有
#   FilmLab / LUT 滤镜 / V-Log 曲线 / 实用功能。
#   代价要说清楚：LUT 从「一键直达」变成「一键进页 + 一按」。
#   EV+AEL 因此空出来，随时可回收复用（脚本仍在，没删）。
#
# ★ 为什么这一页走 mod_gui 而不是 nxui 面板：
#   nxui 是单实例。面板里再 exec `nxui.sh lut` 时，nxui.sh 会看到
#   pidof nxui.arm 命中自己 → killall 自杀 → 「只杀不起」。
#   mod_gui 是另一个进程，`nxui.sh <mode>` 杀掉 mod_gui 再起面板，
#   这正是 gui_func.NX500 里「LUT 滤镜」一直在走的路径，零新风险。
#
# ★ mod_gui 可以指定任意菜单文件作顶层（2026-10-05 从二进制挖出）：
#     传入路径时先试 <path>.<机型>，不可读再试 <path> 本身。
#   loadgui.sh 传 gui_ini 就读到 gui_ini.NX500，机制同此。
#   所以这里直接把 gui_evwifi.NX500 当顶层，不必从主菜单点三层。
#
# 历史备份在机上：/opt/usr/nx-ks/nxui/backup-lut-20261018/EV_MOBILE.sh
#=====================================================================

BB=/opt/usr/nx-ks/busybox
D=/opt/usr/nx-ks
MENU=$D/gui_evwifi

# ---- 机型判定（照抄社区脚本的双条件判据，别凭记忆简化）----
MODEL=$($BB grep -m1 . /etc/version.info 2>/dev/null)
case "$MODEL" in
  NX500) SUFFIX=NX500 ;;
  NX1)   SUFFIX=NX1   ;;
  *)     SUFFIX=NX500 ;;
esac

# ---- 菜单文件存在性（模型感知）----
# ★ argv 这条路【不能带 .NX500】：mod_gui 收到 /x/gui_evwifi 会自己拼
#   <path>.<机型> → gui_evwifi.NX500。若直接传 gui_evwifi.NX500，
#   它会拼成 gui_evwifi.NX500.NX500 然后报 Invalid configuration file
#   并静默退出（2026-11-20 实测）。菜单文件里的 `@...NX500` 是另一条
#   代码路径，那个要带扩展名。
if [ -r "$MENU.$SUFFIX" ] || [ -r "$MENU.NX500" ] || [ -r "$MENU" ]; then
  TARGET=$MENU
else
  nice -n +10 $D/popup_timeout " [ 菜单缺失 gui_evwifi ] " 3 >/dev/null 2>&1
  exit 1
fi

# ---- 切到 LCD 视角（菜单要在 LCD 上才显示得出来）----
# ★ 不用 & 后台：必须等切完，否则 mod_gui 会在 EVF 屏上起，屏幕黑着。
# ★ st 不是 busybox applet，不能写 $BB st（会 "applet not found"）。
if ! st cap capdtm getusr MONITOROUT 2>/dev/null | $BB grep -q LCD; then
  st app disp lcd 2>/dev/null
  $BB sleep 1
fi

# ---- 关掉可能残留的 UI（mod_gui 单实例）----
$BB killall -q mod_gui 2>/dev/null
$BB killall -q onscreen_ov 2>/dev/null
$BB killall -q onscreen_235 2>/dev/null
$BB killall -q popup_entry 2>/dev/null
$BB killall -q popup_ok 2>/dev/null

# ---- 起菜单：直接把合并页当顶层 ----
# ★ DISPLAY 必须显式给：从 ssh/telnet 起来的进程没有 DISPLAY，
#   mod_gui 会报 "Cannot connect to X11 display" 然后立刻死掉。
export DISPLAY=:0
# nice -n +15：让出优先级，拍照时相机主进程优先（社区约定）
nice -n +15 $D/mod_gui "$TARGET" >/dev/null 2>&1 &

exit 0
