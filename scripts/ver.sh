#!/bin/bash
# ver.sh —— Metol 版本与血统（2026-11-20 更新）
#
# 版本号从随包分发的 VERSION 读，改名/升版都不用动本脚本。
# 提示走 nxpopup.sh：面板在跑时由面板自己画（popup_timeout 是独立窗口，
# 会被面板盖住，用户什么都看不到）。
# 每行控制在 ~30 个半角字符内，否则横幅会超出面板宽度。
D=/opt/usr/nx-ks
POP="$D/nxpopup.sh"
[ -x "$POP" ] || POP="$D/popup_timeout"
say() { "$POP" "$1" "${2:-3}"; }

# ★ 先看机身那份。卡上的 /mnt/mmc/VERSION 常常是上一个发行版留下的
#   （2026-11-20 实测还是 2.88.0-nxwa.15.2），拿它当准会显示成"版本回退"。
V=
for vf in "$D/VERSION" /mnt/mmc/VERSION; do
    [ -r "$vf" ] || continue
    V=$(awk '/^version[ \t]+/{print $2; exit}' "$vf" 2>/dev/null)
    [ -n "$V" ] && break
done
[ -n "$V" ] || V="1.15.6"
# /etc/version.info: 第 1 行固件版本（1.12），第 2 行机型（NX500）
FW=$(awk 'NR==1{print $1; exit}' /etc/version.info 2>/dev/null)
CAM=$(awk 'NR==2{print $1; exit}' /etc/version.info 2>/dev/null)
[ -n "$CAM" ] || CAM=NX500

say "Metol $V"
say "$CAM · FW $FW · DRIMe5"
say "血缘 NX-KS 2.88 + 上游 modding"
say "github.com/WApaperplane/metol"
exit 0
