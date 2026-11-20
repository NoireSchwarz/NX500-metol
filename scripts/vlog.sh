#!/bin/sh
# vlog.sh — V-Log 曲线的菜单后端（gui_vlog.NX500 / gui_evwifi.NX500 调用）
#
# 动词：
#   toggle   一键切：没曲线就上曲线，有曲线就回原厂（幂等，UI 主按钮）
#   on       强制上曲线（gamma-reload.sh log，要求当前是原厂）
#   off      强制回原厂 gamma
#   status   打印曲线状态块，不弹窗（命令行/诊断用）
#   gate     跑 V-Log 放行检查，弹窗只给结论，明细落 /tmp/nx-p0/vlog-gate.log
#
# ── 引擎位置 ──────────────────────────────────────────────────────────
# 曲线引擎是 RC5 的 nxl-gamma-reload.arm + lut.sh 一族，**默认没有装进机身**
# （用户明确「暂不安装 RC5」）。这里只认 $D/gamma/ 这一处，不做自动回退去
# SD 卡上跑 —— 菜单误点一下就会改相机 gamma，不能靠"恰好卡在机器里"生效。
#
#   $D/gamma/gamma-reload.sh   引擎入口（连同 bin/ lut.sh data/ 整棵）
#
# 装上之后 gamma-reload.sh 会自己按 $D=脚本目录 校验五个组件 sha256
# （OPS / GAMMA_RELOAD / USB_GUARD / IDLE / REFRESH），所以必须整棵搬，
# 不能只拷一个 .arm。可用 VLOG_ENGINE 覆盖，仅供调试。
#
# ── 为什么 gate 和 toggle 分开 ────────────────────────────────────────
# 放行检查管的是资源层与效果层（A18 回原厂 / PW 中性 / 未插 USB），
# 曲线开关只动 gamma 侧。合成一个按钮就成了「一次点击改两处状态」，
# 出问题无法归因。

BB=/opt/usr/nx-ks/busybox
D=/opt/usr/nx-ks
ARM=$D/vlog-arm.sh
ENGINE=${VLOG_ENGINE:-$D/gamma/gamma-reload.sh}
POP=$D/popup_timeout
GATELOG=/tmp/nx-p0/vlog-gate.log
RUN=/tmp/nx-lut-lite

say() { printf '%s=%s\n' "$1" "$2"; }

pop() {
    # nice +10：弹窗别跟 di-camera-app 抢单核（社区约定）
    [ -x "$POP" ] || return 0
    nice -n +10 "$POP" " $1 " "${2:-3}" >/dev/null 2>&1
}

engine_ok() { [ -f "$ENGINE" ] && [ ! -L "$ENGINE" ] && [ -x "$ENGINE" ]; }

need_engine() {
    engine_ok && return 0
    say ENGINE "MISSING $ENGINE"
    pop "V-Log 引擎未安装" 3
    return 3
}

# 从 gamma-reload.sh 的输出块里摘 mode / phase
field() { printf '%s\n' "$1" | $BB sed -n "s/^$2=//p" | $BB head -n 1; }

do_curve() {   # $1 = toggle | log | restore
    need_engine || return 3
    out=$("$ENGINE" "$1" 2>&1)
    rc=$?
    printf '%s\n' "$out"
    if [ "$rc" != 0 ]; then
        reason=$(field "$out" reason)
        pop "V-Log 失败: ${reason:-rc=$rc}" 4
        return "$rc"
    fi
    mode=$(field "$out" mode)
    case "$mode" in
    LOG)     pop "V-Log 已上曲线" 3 ;;
    FACTORY) pop "已回原厂 gamma" 3 ;;
    *)       pop "完成: ${mode:-UNKNOWN}" 3 ;;
    esac
    return 0
}

do_status() {
    if ! engine_ok; then
        say ENGINE "MISSING $ENGINE"
        return 3
    fi
    "$ENGINE" status
}

do_gate() {
    if [ ! -x "$ARM" ]; then
        say GATE "MISSING $ARM"
        pop "vlog-arm.sh 缺失" 3
        return 3
    fi
    [ -d /tmp/nx-p0 ] || $BB mkdir -p /tmp/nx-p0 2>/dev/null
    out=$("$ARM" arm 2>&1)
    rc=$?
    printf '%s\n' "$out"
    # 明细落盘：弹窗只能塞十几个字，真出问题要看全七项
    printf '%s\n' "$out" > "$GATELOG" 2>/dev/null
    fails=$(printf '%s\n' "$out" | $BB grep -c '=FAIL')
    [ -n "$fails" ] || fails=0
    if [ "$rc" = 0 ]; then
        pop "V-Log 放行 通过" 3
    else
        pop "未放行: ${fails} 项失败" 4
    fi
    return "$rc"
}

case "${1:-}" in
toggle) do_curve toggle ;;
on)     do_curve log ;;
off)    do_curve restore ;;
status) do_status ;;
gate)   do_gate ;;
*)
    echo 'usage: vlog.sh toggle|on|off|status|gate'
    echo "  ENGINE=$ENGINE"
    exit 2
    ;;
esac
