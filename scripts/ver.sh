#!/bin/bash
# 版本号从随包分发的 VERSION 读取，改名/升版都不用动本脚本。
V=$(awk '/^version[ \t]+/{print $2; exit}' /mnt/mmc/VERSION 2>/dev/null)
[ -n "$V" ] || V="1.15.6"
/opt/usr/nx-ks/popup_timeout  " Metol $V " 3
/opt/usr/nx-ks/popup_timeout  " [ Otto: BT模块, 按键扫描, poker, GUI... ] " 3
/opt/usr/nx-ks/popup_timeout  " [ Mewlips: 远程控制器 ] " 3
/opt/usr/nx-ks/popup_timeout  " [ KS: www.fb.com/KinoSeed/ ] " 3
exit
