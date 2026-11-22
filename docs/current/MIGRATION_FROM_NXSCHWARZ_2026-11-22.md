# 从 NoireSchwarz RC6.14.10 迁移功能：能力矩阵与批次（2026-11-22）

对象：`NoireSchwarz/NX500_SRW_reprocessing_6.5K-oversampling` @ `c10f5dd`（2026-11-22 14:18 CET）
本地副本：`E:/NXWA/_ext_rc61410`（`--depth 1`，2280 文件 / 31 MB）；旧副本 `_ext_nx500srw`（R10j, 11-10）
我方基线：Metol 1.15.8（`nx500-modding-work`，分支 `nxwa`）
许可：对方 AGPL-3.0，与我方同证，取用代码不引入新冲突（沿用 [EXT_REVIEW_2026-11-10](EXT_REVIEW_NX500_SRW_2026-11-10.md) 第七节结论）

---

## 0. 一句话结论

对方的架构是**单体 C 前端 + inc 模块 + 分层库**（`base/nx-lut-lite/src/menu_*.inc`、`common/*.h`、
`post/`、`session/`、`lens/`、`hardware/`），我方是**nxui 单体 C + shell 控制器**（`scripts/*.sh` + `lut.sh`）。
两边的 UI 层同为 X11 自绘（`XGetInputFocus` / `XUnmapWindow` / `XRaiseWindow`），所以**交互模块可直接移植**，
不需要换框架。真正重的不是代码量，是**资源事务**（A18、CAP 池、P0 门控）。

最有价值的三条增量，按边际价值排序：

1. **WiFi 双频 SoftAP 相簿**（我方完全没有：我方是 STA 模式连路由器，80 端口出图）
2. **SRW 机内重显影整链**（我方只有 `/mnt/mmc/nx-srwcap` 能力层，未真跑）
3. **LUT 面板交互模型**（我方已有 mix/strength，差 UI 语义：OK 装载、半按返回、详情页、输入独占）

---

## 1. ★ 一条需要修正的旧结论：5GHz

`WIFI_5GHZ_FINAL_2026-11-20.md` 的收尾是「射频通路存在与否，只有发射能回答——本线到此为止」，
全程零发射。对方 RC6.14.9 的实测把它回答了：

| 项 | 对方实测（HANDOFF_20261122） |
|---|---|
| 2.4 GHz 相簿 | 平均推送 27.95 fps，跳帧 6.8%，TCP 重传 0 |
| 5 GHz 第一段 | 26.05 fps，跳帧 12.7%，重传 80 |
| 5 GHz 贴机近场 | 起播约 9.9 s 后稳定 ~30 fps |
| 5 GHz 相簿大档长传 | 6.19 MB/s |

⇒ **NX500 的 5G 射频通路存在且可发射**，与 11-20 的固件侧证据（`fw_bands=0x6f`、663 B 功率表、
NX1/NX30 同腔体 FCC 认证）一致。我方「停止」决定的正确表述是「**零发射纪律下的研究终止**」，
不是「硬件不支持」。

合规提示：2.4 GHz 全球通用；5 GHz 的 5150–5350 MHz 在中国限室内、5725–5850 MHz 免许可。
建议 **默认 2.4 GHz，5 GHz 作为显式选项**，菜单文案不写「增强/破解」。

---

## 2. 能力迁移矩阵

| # | 能力块 | 对方载体 | 我方现状 | 代价 | 依赖 | 风险 |
|---|---|---|---|---|---|---|
| **B1** | WiFi 双频相簿 + RVF 图传 | `src/wifi_hotspot.h` `wifi-server.c` `wifi-radio.c` `menu_wifi.inc` `wifi.sh` `qrcodegen.c` + `wifi_*.h` 共 ~40 文件 | STA 模式 80 端口 web 相册（`scripts/nx-rc/thumb` + `web_root`），无 SoftAP、无 5G、无 RVF | 高 | 原厂 `di-camera-app` 运行中 | 低（不动 ISP/内存） |
| **B2** | LUT 面板参数化交互 | `menu_lut_picker.inc` `menu_lut_detail_v2.inc` `menu_input_lease.h` `menu_window_policy.h` | nxui 720×208 自绘，`lut.sh mix/strength` 已有 A/B 混合；差 OK 装载/半按返回/详情页/输入独占 | 中 | A18 事务（`lut.sh`） | 中 |
| **B3** | SRW 机内重显影 | `post/src` `common/{srw_tone_curve,jpeg_ticket,album_output,shared_workspace}.h` `session/` | `/mnt/mmc/nx-srwcap`（61 文件）能力层已铺、`--status` 通，未真跑 | 极高 | 176 MiB CAP 事务，与 A18 互斥 | 高 |
| **B4** | 全宽视频档位 | `hardware/src`（video-mode / video-fullwidth / hevc patch）`native/libmmfcore.r11f.so` | 2.5K 全宽映射（画幅 98.79%），PAL 25p | 高 | .so 补丁 + DYN24 槽 | 中 |
| **B5** | V-Log 8bit + 曲线重载 | `common/gamma_reload.h` `nxl-gamma-reload.arm` R11H 系列 | `vlog.sh` + gamma 引擎 + TC 互斥，**我方更成熟** | 低 | — | 中 |
| **B6** | 身份守卫 + 清单绑定 | `runtime_identity.py` `lens/rom-identity.h` `lens/udd-identity.h` `installer/` | `gamma-reload.sh` 哈希链（USB_GUARD/GAMMA_RELOAD/IDLE/REFRESH/OPS+ENGINE）+ `usb-guard` | 中 | — | 低 |

横切项 **B6** 不单独成批：每迁入一块，就把它的二进制纳入现有哈希链，沿用「改二进制即断链」的纪律。

---

## 3. 逐块要点

### B1 · WiFi 双频相簿

对方的机制（读源码确认，非文档转述）：

- **热点壳**：不替换原厂网络守护进程，直接调原厂 SoftAP 入口起壳（`hotspot` / `hotspot24` / `rvf` 三个命令），
  进程内存只读。
- **密码来源**：从 `di-camera-app` 的 preference 页只读取原厂热点密码——`HOT_PREF_PHYSICAL=0x85480000`、
  `HOT_PREF_BYTES=0x11000`、`HOT_PASSWORD_OFFSET=0x106e3`，映射 `/dev/mem` 后**双读比对**（a/b 两次 memcmp）
  并复查 `/proc/PID/maps` 的 VMA（`/dev/mem`、`rw-s`、offset 匹配、页对齐、长度精确 0x11000、唯一命中）。
- **入口表**：`{"5 GHz 相簿","?view=media","hotspot"}` / `{"2.4 GHz 相簿",...,"hotspot24"}` / `{"2.4 GHz 圖傳",...,"rvf"}`。
- **页面**：`wifi-server.c` 起网页 + 双码二维码（两枚 QR：连接用 SSID/密码、页面用 URL），`?view=media` 相簿、`?view=rvf` 图传。
- **串行保护**：进 2.4 GHz 相簿前核实无未恢复的 5 GHz 租约；RVF 只接受原厂 2.4 GHz 频率（5 GHz RVF 已从菜单移除）。

迁移做法：**内容后端不换**（我方 `thumb-cgi` + `nxthumb.arm` 已比对方快：网格 148 ms、灯箱 759 ms），
只取对方的「起壳 + 取密码 + 双码」三件事，挂到我方 web_root 前面。

### B2 · LUT 面板交互

我方已有：`lut.sh list/fav/move/del/index/stock/mix/strength/apply/off`、`lutmix.arm`（5164 B, md5 `addae113`）。
缺口是 UI 语义：

| 对方行为 | 我方现状 |
|---|---|
| 编辑参数后 **OK 才装载**，装载保持菜单 | 点选即换表 |
| **半按返回**且保留效果 | 半按关面板（一致） |
| **双击 EV** 打开当前 LUT/Log LUT 详情页 | 双击 EV 开主菜单 |
| 二级窗口**输入独占**（父进程持锁，子进程只关副本） | 换层清 `q.due`，但无输入租约 |
| M3 **独立强度 A/B** 混合 | `lut.sh mix` 已有，UI 未暴露 |

### B3 · SRW 重显影

对方整链：`SRW → BayerStill → LDC → 可选 EP 3D LUT → JPEG`，一次申请 192 MiB 工作区，
源片 WB / 颜色矩阵 / C0 19 点 gamma / JPEG 量化表全部从源片继承。
关键纪律：与 A18 LUT 事务**互斥**（对方 RC4 明确「新加载器与 SRW 工作锁互斥，SRW 自己的清理跳过新硬件入口」）。

我方 11-20 已铺能力层，真跑需 176 MiB CAP 事务，与取景/录像/LUT 全串行。**B3 必须排在 P0 门控之后**。

### B4 · 全宽视频

对方当前只认原生 24p（R11G）。我方 2.5K 映射画幅 98.79%，落在同一读出窗口族
（他 6608×3680 有效 6496×3644 origin 92,36 stride 9920；我 ≈6654×3680）。
迁移价值点在**档位切换与恢复**（`video-mode` 三个动作），不在超采帧率——掉帧未解，对方自己标为研究态。

### B5 / B6

B5 我方更成熟（`vlog.sh` + gamma 引擎 + TC 互斥 + `FILMLAB_PW=1 filmlab.sh neutral` 只直推 ISP 不写 prefman 槽 9-12）。
只需对照对方的 `gamma_reload.h` 排队确认语义。B6 取其 VMA 唯一性校验思路，补进我方守卫链。

---

## 4. 批次与门控

| 批次 | 内容 | 前置 | 出口判据 |
|---|---|---|---|
| 1 | B1 起壳 + 取密码 + 双码（先 2.4 GHz） | 无 | PC 端 `wifi_hotspot` 单元回放 + 机端 2.4 GHz 相簿可下载原档 |
| 2 | B2 交互语义（OK 装载 / 输入独占 / 详情页） | 批 1 不触碰 A18，可并行 | `test_layers_2b.py` 全绿 + 面板手感复核 |
| 3 | B3 SRW 试跑（单张，A18 备份在位） | P0 门控 253/253 + 470/470 | 单张 SRW → JPEG，源片参数继承逐项对照 |
| 4 | B4 档位切换 | `.so` 补丁 SHA 纳入哈希链 | 三档切换 + 恢复原厂，录像不黑屏 |
| 5 | B5/B6 收口 | 全部 | 哈希链全绿，`preflight` 无回退项 |

**硬门控（沿用 P0）**：任何一块触碰 A18 / CAP / 录像 fd 的，必须先过
`docs/current/P0_EXECUTION_PLAN_2026-11-20.md` 的守卫判据，不得先上机再补测。

---

## 5. 明确不迁

| 项 | 理由 |
|---|---|
| 全宽 30p 超采 | 对方自标研究态，掉帧未解（缺口 ~8.9 ms/帧），我方 11-07 位深结论锁死收益上限 |
| 8bit V-Log 色彩标定 | 对方自己标为边界（无物理 18% 灰独立标定，MP4 色彩标签未改写） |
| `hevc-gate` 的 `.so` 补丁链 | 依赖对方 `native/libmmfcore.r11f.so` 特定版本，跨包移植即断链风险 |
| 对方 installer 整套 | 我方已有 `install.sh` + `pack_release.py` + 双语双包，不换 |

---

## 6. 已核实的实现细节（读源码得出，非文档转述）

### 6.1 5GHz 是三重条件，不是"改一个位"

我方 11-20 查的是 mlan 驱动侧 `dev_cap_mask`（`0xffffcbff`）。对方走的是另外三层：

| 层 | 载体 | 值 / 做法 | 是否落盘 |
|---|---|---|---|
| ① 频段使能字 | `/dev/mem` 物理 `0x85440068` | `0` → `1` 单字写；窗口 `0x85400000 + 0x40000 + 0x68` | 否（RAM） |
| ② 规范域模块 | `wireless/cfg80211-cn-low5g.ko`（208780 B，原厂 208716 B） | 复制到 `/tmp` 再 insmod，不替换盘上模块 | 否（RAM） |
| ③ AP 起壳 | 原厂 `/usr/bin/st` | `st app softap start` | 否 |

①的地址不是猜的：从 `libuser-spec.so`（194760 B）的 GOT 解析 `R_ARM_COPY` 字
（`US_ROOT_GOT=0x37330` → `US_ROOT_APP_COPY=0x0049d0f8` → 解引用得 root → `root+0x68`），
再校验该地址落在 `/dev/mem` 的 `rw-s` 映射、offset `0x85400000`、长度 `0x81000`、
且 `lo+0x40000==root` ⇒ 物理恰为 `0x85440068`。四处代码 guard（`0x70a4`/`0x73a0`/`0x4774`/`0x106b4`）
逐字节比对通过才读写，读完双次比对确认非竞态。

②的效果用 nl80211 **只读**查询自证：`GETFAMILY` → `GET_INTERFACE(uap0)` → `GET_WIPHY` → `GET_REG`，
要求 CN 域只有两条规则 —— `2402–2482 @40 MHz flags=0` 与 `5150–5250 @80 MHz flags=8`（室内），
且 wiphy 报告 5220/5240 两信道 `present==allowed`。缺一条即拒。

**实际只开 CH48 @ HT40-minus（5180 MHz），明确拒绝 VHT80**
（`ap_width.h` 只接受 bandcfg `0x31`/`0x39`，`0x3d` 直接判失败）。

### 6.2 SoftAP 起壳不需要对方的二进制

`hot_start()` 的做法是 `execl("/usr/bin/st","st","app","softap","start")`，然后轮询
`di-camera-app` 进程内存等 `state∈{1,2,11}` 且 `uap0` 有 IP。读取点：
状态/SID 在 `0x4a8e08`、`0x4a8e38`、`0x4a8e84`、`0x4aeab8`；密码走 preference 物理页
`0x85480000 + 0x106e3`（`0x11000` 窗口，双读比对 + VMA 唯一性校验）。

⇒ 我方**不需要搬 30 个 wifi 源文件**就能起 AP。`st` 我方本来就有。

### 6.3 编译链结论（实测）

在 WSL `NXKS2`（`arm-linux-gnueabi-gcc 13` + `/opt/nxks2/rootfs-112`）上直接编 `wifi-server.c`：
**编译通过，仅 2 条 `-Wformat-truncation` 警告**；但按我方 glibc-2.13 配方链接会断在
`__isoc23_strtol/sscanf`、`fstat64`、`lstat64` —— 对方是用 **musl 静态**编的，我方 rootfs 是 glibc 2.13。

两条路（择一）：
1. **取 release 成品二进制**（musl 静态，无 libc 依赖）：`nxl-wifi-server` 169076 B，
   只把 web 目录作为参数传入，`INSTALLED` 路径只被 `nxl-wifi-radio` 用到（可改我方路径重编）。
   ⇒ 推荐，代价最低；用 SHA256 绑进我方哈希链。
2. 自编：加 `-include` compat shim（`__isoc23_*`→`__isoc99_*`，`fstat64`→`__fxstat64(_STAT_VER,…)`）。
   可用但每换一版都要重打，不推荐。

### 6.4 源码闭包规模（已入库）

`wifi-radio.c` 的完整 include 闭包 = **37 文件 / 251 KB**，无缺失。
已拷入 `scripts/nx-rc/wifi/src/`（保持原相对路径）。

---

## 7. 2026-11-22 晚：CH48 定案 + 全宽 24p 入库

用户决定：**5 GHz 走 CH48**（`cfg80211-cn-low5g.ko`），**全宽 24p 一并迁入**。

### 7.1 已落地的运行时组件

| 路径 | 内容 | SHA256（前 16） |
|---|---|---|
| `scripts/nx-rc/wifi/nxwifi.sh` | 221 行；`start24 / start5g / stop / status` | — |
| `scripts/nx-rc/wifi/bin/nxl-wifi-server` | 169076 B，ELF32 ARM static | `3be9431de8f70002` |
| `scripts/nx-rc/wifi/bin/nxl-wifi-radio` | 253372 B | `4b10b8bddc31562c` |
| `scripts/nx-rc/wifi/modules/cfg80211-cn-low5g.ko` | 208780 B，vermagic `3.5.0 preempt mod_unload ARMv7 p2v8` | `2c8ef0dd538d667a` |
| `scripts/nx-rc/video/nxvideo.sh` | 视频档位壳；`status / full / uhd / 2k / crop80 / usb-check` | — |
| `scripts/nx-rc/video/bin/*` | `nxl-video-mode` `nxl-video-fullwidth` `nxl-video-probe` `nxl-native-refresh` `nxl-usb-guard` `nxl-fileops` | 与 RC6.14.10 **逐字节相同** |

### 7.2 5 GHz 起壳序列（CH48）

```
SRV --web-stop
RADIO --prepare            # band word /dev/mem 0x85440068 0→1 + cfg80211-cn-low5g.ko 复制到 /tmp 后 insmod
SRV --hotspot-start        # st app softap start → 等 uap0 就绪
RADIO --confirm-profile    # 等 RTOS 上报 uap0 频率 == 5180 MHz，7.5 s 超时
```
任一步失败即 `RADIO --stop`（还原 band word + 恢复原厂 cfg80211）再 `SRV --stop`。

`nxl-wifi-radio` 的 `INSTALLED` 是编译期常量 `/opt/usr/nx-lut-lite`，`nxwifi.sh` 的
`ensure_nxl_layout()` 会按 SHA 把 server/radio/ko 铺到该目录（只在缺失或不一致时复制）。

### 7.3 全宽 24p 的既有资产

`full` 走的五步（`native_reload video24 → check24p → uhd → apply → 24p → 再 reload`）
与对方一致；六个二进制我方 `_ext_rc5/nx-srwcap/bin` 里**早就有了，且与 RC6.14.10 完全相同**，
所以这块的迁移成本只是写壳 + 接菜单，不需要重新取包。

`libmmfcore.r11f.so`（434176 B，hevc-gate 的 .so 替换）**仍未取用**——`full` 路径不依赖它，
它是 `crop80` / 高清录制码率那条的补丁件。要用再单独评估。

### 7.4 安装链接线

`install.sh` 的 chmod 兜底循环已扩展到
`nx-rc/wifi/*`、`nx-rc/wifi/bin/*`、`nx-rc/video/*`、`nx-rc/video/bin/*`
（原先只盖到 `nx-rc/*` 一层，子目录里的可执行位不会被补，会表现为“装完没反应”）。

---

## 8. UI 接入（2026-11-22 晚，已上机验证）

### 8.1 ★ 第一版为什么会被打回

第一版直接改了 `/opt/usr/nx-ks/gui_ini.NX500`，用户一按菜单就变回旧内容。
原因：**`gui_ini.NX500` 不是配置，是产物** —— `menu.sh` / `loadgui.sh` 在起菜单前先跑
`gen_menu.sh`，它用 `gui_tpl.NX500`（含 `%%IP%%` / `%%TN%%` 占位）渲染并**覆盖** gui_ini。

⇒ **改主菜单必须改 `gui_tpl.NX500`**，改 `gui_ini.NX500` 只在当前这一次有效。

（顺带记一个坑：机上的 `gui_ini.NX500` 之所以和我本地不同，就是它带运行时渲染出的 IP 行。）

### 8.2 最终布局

| 文件 | 内容 |
|---|---|
| `scripts/gui_tpl.NX500` | 主菜单加 `视频档位`（8 项） |
| `scripts/gui_settings.NX500` | 末端加 `Wi-Fi 相簿`（点进去才是 5G/2.4G） |
| `scripts/gui_video.NX500` | `4K 全宽 24p` / `4K 原生 30p` / `2.5K 输出` / `裁切80% 30p` |
| `scripts/gui_wifi.NX500` | `开 5 GHz 相簿` / `关热点回联网` / `开 2.4 GHz 相簿` |
| `i18n/en/scripts/` 同名四份 | 英文包 |
| `test_server/nxui/nxui.c:1132` | 标题 `NX-KS  /  菜单` → `Metol  /  菜单`，重编 arm |

机端实测：`items=8 / 9 / 4`，三张 720×292 截图逐项核对通过（见 `_push_tmp/m1-3.png`）。

**注意**（`nxui_model.c::nx_load_menu`）：`返回`/`取消` 两行故意不渲染——顶栏常驻「返回/关闭」。

### 8.3 推文件的两个必做动作

1. **`chmod 755`**：`push` 过去的 `nxui.arm` / `*.sh` 全是 644，直接跑报 `Permission denied`（RC=126）。
2. **同步 SD 母本** `/mnt/mmc/scripts/`：`install.sh` 是 `cp -ar /mnt/mmc/scripts/* /opt/usr/nx-ks/`，
   母本不更新，下次装机就打回旧版。

已同步：`gui_tpl` / `gui_settings` / `gui_video` / `gui_wifi` / `nxui/nxui.arm` / `nx-rc/{wifi,video}`。

---

## 9. 5 GHz 首次上机：射频全通，卡在状态门（2026-11-22 22:28）

### 9.1 已证实成功的部分（日志实证）

```
cfg80211: Regulatory domain changed to country: CN
cfg80211:   (2402000 KHz - 2482000 KHz @ 40000 KHz), (2000 mBi, 0 mBm)
cfg80211:   (5150000 KHz - 5250000 KHz @ 80000 KHz), (10000 mBi, 0 mBm)   ← 5G 规则已生效
wlan: Loading MWLAN driver → FW already running → Driver loaded successfully
WIFI5G phase=4 CFG_FREQUENCY mhz=5180 disabled=0 no_ir=0 no_ibss=0 radar=0 no80=0
WIFI5G phase=4 CFG_CN_PROFILE_CHANNELS_READY
WIFI5G phase=5 AP_LAUNCH_BOUND
```

⇒ band word 写入、`cfg80211-cn-low5g.ko` 换入、SDIO 重新上电（`support_card=1`）、
hostapd 劫持（bind mount）**全部成立**。卡点不在射频。

### 9.2 两个卡点

**卡点一：`AP_LEASE_LOST`（已修）**

`ap_relay()` 第一句是 `live_identity(trial.owner, trial.owner_tick)`，它比对
`/proc/<pid>/exe == /opt/usr/nx-lut-lite/bin/nxl-wifi-radio`。而脚本从
`/opt/usr/nx-ks/nx-rc/wifi/bin/` 起进程，exe 路径不符 ⇒ 守护进程判定租约丢失。

修法：`nxwifi.sh` 在 `ensure_nxl_layout()` 之后把 `SRV` / `RADIO` 重指到
`/opt/usr/nx-lut-lite/bin/` 下的副本。

**卡点二：`STOP_EXISTING_WIFI_FIRST`（未解）**

`baseline()` 要求 `di-camera-app` 的 AP 状态字 `0x4a8e38` 为 **0**。
本机实测该字稳定在 **10**，`st app softap stop` 返回 0 但它不回 0。
只要不是 0，radio 就拒绝进入准备流程。

`ap_state` 语义（来自源码）：
- `1/2/11` = AP 就绪（`hot_snapshot` 的 ready 判据）
- `10` = 关闭中/中间态（`band_restore_gate` 把它当"已关"接受）
- `0` = 完全关闭（`baseline` 唯一接受的值）

⇒ 需要在 AP 状态真正归零的时刻执行，或先让原厂完整走一次 起→停。

### 9.3 手工清理过的残留

首次失败的 `restored=0` 把 band word 留在了 `1`。已用
`busybox devmem 0x85440068 32 0` 写回（读前 `0x1`、写后 `0x0`），
并删除 `/tmp/nx-lut-lite/wifi-hotspot.owner`、`wifi-radio/`、`controller.log`。
当前相机：`mlan0` 正常、无 `uap0`、band word = 0（原厂状态）。

### 9.4 一个数值更正

**CH48 = 5240 MHz**（CH36 才是 5180）。radio 的 `frequency_expected_mhz=5240` 印证。
脚本文案里"CH48 / 5180 MHz"写错了，实际期望值以 `NXL_AP_MHZ` 为准。

### 9.5 A 方案（起停 2.4G 复位状态）→ 失败

用 `ap-reset.sh` 让原厂完整走一次 起→停：

```
start rc=0
uap0 ip=none after 60s          ← AP 根本没起来
AFTER_START ap_state=10
stop rc=0
uap0 gone after 0s
AFTER_STOP  ap_state=10         ← 状态字没变
```

更关键的是 `/var/log/messages`：22:41 这次**完全没有** `org.tizen.tethering` 激活记录
（22:28 radio 劫持那次有两条）。⇒ `st app softap start` 在当前状态下**空转**，
原厂 tethering 服务压根没被拉起。

模块侧是干净的：`lsmod` 里 `cfg80211` 已回原厂，`/tmp/nx-lut-lite/cfg80211*` 已清空。

结论：**先要证明原厂 SoftAP 本身能起来**（相机屏幕上手动开「移动 AP」），
再谈 radio 的 5G 劫持。原厂都起不来时，radio 的 `AP_LEASE_LOST` / `NATIVE_AP_START_DID_NOT_COMPLETE`
只是同一个上游症状。

最省事的复位顺序：冷启动相机 → 开机后 `ap_state` 应为 0 → 立刻跑 `nxwifi.sh start5g`。

---

## 10. 离线重启验证：radio 全通，卡在原厂 AP 未起（2026-11-22 22:51）

### 10.1 为什么必须离线

第二次尝试报 `STATION_CONNECTION_PRESENT`。读 `probe.h::radio_baseline()`：

```c
else if(power==1&&mask==7&&sta==1&&ap==0){
    ...
    if(interface_ip("mlan0",ip))return failed("STATION_CONNECTION_PRESENT");
}
```

要求 **mlan0 接口在（sta==1）但没有 IP**。而 SSH 正是走 mlan0 的 IP ⇒ 必须机端分离执行。
写了 `start5g-offline.sh`：`wpa_cli disconnect` → `ifconfig mlan0 del <ip>`（busybox 不吃 `0.0.0.0`，
只支持 `del ADDRESS[/PREFIXLEN]`）→ 跑 start5g → 失败则 reconnect。调用方 `setsid` 分离。

### 10.2 这一轮 radio 侧全部通过

```
after: mlan0 ip=none (0s)              ← 前置条件够了
BAND_READ value=1 ... BAND_WRITE_VERIFIED   ← 频段字写入成功
BAND_LEASE_RETURNED, BAND_READ value=0      ← 回滚也正确还原
```

即：基线检查、频段字、模块换入、bind mount 全过。
`result.txt` 最终 `reason=NATIVE_PENDING_DEFAULT_STA_NOT_RECREATED`、`modules=0 mlan0=0`
——回滚时驱动栈没重建，相机随后自己恢复了 STA。

### 10.3 真正的卡点：原厂 SoftAP 没被拉起来

```sh
$ ps | grep -E "mobileap|tethering"     # 空
$ tail /var/log/wlanplug_log
22:51:06 called by net-config CMD: softap   ← 命令到了 net-config
22:51:08 called by net-config CMD: stop     ← 我们回滚
```

对比 22:28 那次成功的形状：`/var/log/messages` 里有
`Activating service name='org.tizen.tethering'` + `Successfully activated`。
22:41 / 22:51 两次**都没有这两行**，`mobileap-agent` 也不在进程表里。

⇒ `st app softap start` 把命令送到了 `net-config`，但**下游的 tethering 服务没被 dbus 激活**，
AP 自然不会起。所以 `HOTSPOT_START_PENDING` / `ap_state=10` 是上游症状，不是 radio 的问题。

### 10.4 待确认

在相机屏幕上手动开一次「移动 AP」（设置 → 移动 AP / Mobile AP）：

- 手动能开 ⇒ `st app softap start` 不是完整入口（或缺前置），要去抓屏幕操作时的命令与 dbus 日志
- 手动也不能开 ⇒ 原厂 tethering 服务本身挂了，先修它（重启后仍不行的话，可能与我们早前
  劫持 hostapd 有关，需要核对 `/usr/sbin/hostapd` 是否已还原）

`/usr/sbin/hostapd` 的还原状态可以这样只读核对：大小 396764、FNV `0x76b05ce9`
（`ap_launch.h` 的 `AP_STOCK_BYTES` / `AP_STOCK_FNV`），且不该有任何 mount 挂在它上面。

---

## 11. 两条链路并存（2026-11-23 00:12 定稿）

用户定的菜单语义：**局域网相册** 一个入口，**相机热点** 下挂 5 GHz / 2.4 GHz。
「断开 WiFi」从菜单删除（系统应用里有）。

| 位置 | 项 | 命令 |
|---|---|---|
| 系统设置 | 局域网相册 | `nxwifi.sh album` ✅ 已验证 |
| 系统设置 → 相机热点 | 5 GHz | `nxwifi.sh start5g` |
| 系统设置 → 相机热点 | 2.4 GHz | `nxwifi.sh start24` |
| 系统设置 → 相机热点 | 关闭热点 | `nxwifi.sh stop` |

旧文件 `gui_wifi.NX500` 已删（机端 / SD 母本 / 仓库），避免两处引用。

### 11.1 `album`：局域网链路（已验证）

取 `mlan0` 地址 → 屏幕 `popup_timeout " [ http://<ip>/ ] " 5` → 日志记 URL。
内容后端就是现有的 `scripts/nx-rc/thumb` + `web_root`（`thumb-cgi` / `nxthumb.arm`）。
实测：`ALBUM http://192.168.0.104/`、`http://192.168.0.104/` 返回 `HTTP 200`，首页 12385 B。

### 11.2 `start5g` 自包含

`radio_baseline()` 要求 `mlan0` 在但无 IP。`start5g` 现在自己先
`wpa_cli disconnect` + `ifconfig mlan0 del <ip>`，失败路径再 `reconnect`。

### 11.3 ★ 热点链路「没有设置好」的真相：缺的是生成配置的 agent

读 `wifi_radio/ap_config.h::render_ap_config()`，它期待一个**由原厂 agent 刚生成**的
hostapd 配置文件，要求 10 个字段齐全且取值精确匹配：

```ini
interface=uap0
driver=nl80211
hw_mode=a          ← 5 GHz
ieee80211n=1
ieee80211ac=1
channel=36
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
wmm_enabled=1
```

relay 把它改写成 `channel=48`（`NXL_AP_PRIMARY`）、`ieee80211ac=0`、`vht_oper_chwidth=0`、
center=`46`、width 40 MHz。

两个含义：

1. **三星原厂 mobileap-agent 本来就会生成 5 GHz 配置**（`hw_mode=a`, `channel=36`），
   被挡住的只是驱动的 `dev_cap_mask`。⇒ 5 GHz 不是"改出来的"，是原厂留了但没开。
2. 我们卡住的不是配置内容，而是**没人生成这个文件**——`mobileap-agent` 不跑，
   `org.tizen.tethering` 没被 dbus 激活，relay 无文件可改。

**可尝试的绕法**：自己按上面模板手写 `hostapd.conf`（`channel=36` 必须原样，否则 relay 拒改），
在 `radio --prepare` 之后直接 `exec /usr/sbin/hostapd <conf>` ——此时 `/usr/sbin/hostapd`
已被 bind mount 成 `nxl-wifi-radio`，即走 `ap_relay()`，不需要原厂 agent。

---

## 12. 待办

- [x] B1：读 `wifi.sh` 全文，确认起壳命令与状态回报协议
- [x] B1：确认 5GHz 三重条件与 CH48 HT40-minus 契约
- [x] B1：源码闭包 37 文件入库 `scripts/nx-rc/wifi/src/`
- [x] B1：取 release 的 `nxl-wifi-server`，绑 SHA256，写 `nxwifi.sh` 包装（`start24|start5g|stop|status`）
- [x] B4：`nxvideo.sh` + 六个二进制入库（与 RC6.14.10 逐字节相同）
- [ ] B1：上机跑 `nxwifi.sh start5g`（会断 STA，需有人在场）
- [ ] B1：nxui 加 WiFi 入口页（5 GHz 相簿 / 2.4 GHz 相簿 / 2.4 GHz 图传），复用 `qrcodegen.c`
- [ ] B4：nxui 视频页接 `nxvideo.sh full|uhd|2k`
- [ ] B4：上机验证三档切换 + 恢复原厂不黑屏
- [ ] B2：给 `nxui` 加 `menu_input_lease` 等价物（父持有、子关闭副本）
- [ ] B3：核对 `nx-srwcap` 与对方 `post/src` 的接口差异清单
