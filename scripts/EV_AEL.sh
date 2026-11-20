#!/bin/bash
#=====================================================================
# EV_AEL.sh —— EV + AEL：本槽位不绑定任何功能（2026-11-20 修正）
#=====================================================================
# ★ 上一版错在哪：
#   我把 `EV_AEL.community.sh` 当成"AEL 锁定"一类的无害社区脚本，就
#   `exec` 了它。实际它是**黑屏录像器**：
#       blackoutprep &  → killall onscreen_ks + 起 blackout（整屏黑）
#       blackouton      → st app led off
#       循环 10 分钟     → stapp "app nx record start" / stop
#   于是按一下 EV+AEL 就整屏黑 —— 用户报的"黑屏没修复"就是这个，
#   与 V-Log 无关。
#
# ★ 现在的语义：什么都不做。滤镜入口只有 EV+WiFi 一个（面板里 WiFi / AEL
#   换层）。community 那个黑屏录像脚本**保留在机器上**
#   （/opt/usr/nx-ks/EV_AEL.community.sh），想用就手动 sh 它，但不再占键。
#
# ★ 如果屏幕已经被它弄黑，手动恢复：
#       killall -q blackout
#       nice -n +15 /opt/usr/nx-ks/onscreen_ks &
#=====================================================================
exit 0
