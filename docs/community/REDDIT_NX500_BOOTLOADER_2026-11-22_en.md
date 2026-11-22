# Reddit post (EN) — 2026-11-22 / NX500 bootloader

> Subreddits: r/SamsungNX, r/VintageDigitalCameras, r/cameras.
> Flair: "DIY / Repair" or "Discussion".
> Angle: one finding stated flat, plus where the evidence stops. No "I cracked it".
> Everything here is read-only analysis — no partition was written, no hardware opened.
> Repo: https://github.com/WApaperplane/nx500-dnloader

---

## Title options

1. **NX500's bootloader has a built-in recovery shell — and `dnloader.bin` may be unnecessary** ← 推荐
2. NX500 firmware recovery: what `dnloader.bin` was supposed to do, and a 912-byte replacement
3. Reverse-engineered the NX500 bootloader, found a shell nobody documented

---

## Body

`dnloader.bin` for the NX500 has never leaked. That's why a corrupted eMMC boot
partition means a dead camera — Main PCB Recovery (service manual §7-6) cannot run.

So I disassembled the camera's **own** `boot0.bin` (4 MiB partition dump) and
cross-checked every address against Samsung's official NX500 GPL source tree.
Three things fell out:

**1. boot0 has a shell.** Send a CR over UART while it boots — you land in
`bootloader>` with `test flash read`, `test flash erase`, `test ddr` and
`boot [mode]`. That is already a recovery tool. It's undocumented.

**2. The "recovery" branch is the SD path.** Before printing
`Starting A9 for recovery.`, boot0 raises SD card power (GPIO 179), then loads
to `0x86007FC0` and jumps. That matches the service manual's SD-card procedure,
and it means the camera has a recovery path we never knew about.

**3. DRAM init is not ours to reverse.** bootROM already did it — boot0's stub
literally does `mov pc, #0x80000000`. That removes the step everyone assumed was
the blocker for writing a custom dnloader.

So instead of porting another model's bootloader, I wrote a **912-byte
position-independent skeleton**. It has no absolute addresses and no stack usage
(bootROM leaves SP = 0), and it prints its own load address plus a UART
self-check — so one power cycle answers the questions that are still open.

Verified by actually executing it in QEMU (vexpress-a9 / Cortex-A9): linked at
0, run at `0x60100000`, correct output. **Never run on real hardware — I don't
have a UART tap on my NX500.**

Repo with the full hardware constant table, boot0 disassembly notes and source:
https://github.com/WApaperplane/nx500-dnloader

---

**On the UART question — two things worth knowing before anyone else spends a weekend:**

First, **the micro-USB route is dead.** The board does carry a TI TSU6111RSVR USB
mux (it's in the service manual BOM), and in 2016 two people independently tried
the resistor trick on NX500: ge0rg with a USB-OTG-UART cable at 150K/620K, and
vasile with a proper micro-USB breakout and the resistor between ID and GND,
plugged in before power-on. Neither got a single byte. vasile ended up sending
the camera in. (ge0rg/samsung-nx-hacks issue #7, dpreview thread from May 2016.)

Second, **boot0 initializes the UART itself** (0x2000bc8), so "there should be a
log at power-on" is an unsafe assumption — before boot0 reaches that call the
port may be silent.

What's actually missing is location, not skill: the community has long referred
to a **2x4 contact pad** on the mainboard (visible in the iFixit *NX300* guide),
but nobody has confirmed where that pad is on NX500 or whether it even is UART.
The service manual's board block diagram lists SD, USB, HDMI, MIPI, I2S and
MUIC — **no UART** — so the port may only exist on test pads, and the component
table gives pad part numbers without signal names.

**What would close this:** a photo. Someone who has an NX500 open (or a bricked
one they're willing to open) takes a high-res shot of the mainboard, and we
identify the pad group together. After that, soldering three wires and running
`dnloader.bin` is a half-hour job. What would also help just as much: a full
serial boot log from anyone who already has a tap.

---

## 发布前检查

- [ ] 仓库 README 的"未验证清单"确实如实（真机加载 / bootROM 文件名 / SD 初始化 / 四 GPIO 是否短接点）
- [ ] 不要写成"我做出来了 dnloader"——只有骨架 + 常量表
- [ ] 强调只读：没有写任何分区
- [ ] 如果有人回应有 UART，优先问：能否 dump 一份完整的串口启动日志（这才是最有价值的数据）
