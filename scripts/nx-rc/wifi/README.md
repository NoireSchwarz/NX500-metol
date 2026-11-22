# nx-rc/wifi — SoftAP 相簿壳（迁移自 NoireSchwarz RC6.14.10）

来源：`NoireSchwarz/NX500_SRW_reprocessing_6.5K-oversampling`（AGPL-3.0），
上游 `WApaperplane/metol` 与 `ottokiksmaler/nx500_nx1_modding`。
迁移记录与逐块矩阵见 `docs/current/MIGRATION_FROM_NXSCHWARZ_2026-11-22.md`。

## 文件

| 文件 | 说明 |
|---|---|
| `nxwifi.sh` | 相机端壳：`start24` / `stop` / `status` / `start5g`（预留） |
| `src/` | 对方的 WiFi 源码闭包（37 文件 / 251 KB，保持原相对路径），未参与构建 |

## 为什么先只做 2.4 GHz

起 SoftAP 的原厂入口是 `/usr/bin/st app softap start`，我方本来就有 `st`，
不需要对方的二进制也不需要写任何内存。5 GHz 则是三重条件：

1. `/dev/mem` 物理 `0x85440068` 单字 `0`→`1`（频段使能；地址经 `libuser-spec.so` GOT 解析得出）
2. `wireless/cfg80211-cn-low5g.ko`（208780 B）复制到 `/tmp` 后 insmod，不替换盘上模块
3. 同样的 `st app softap start`，之后只开 CH48 / 5180 MHz / HT40-minus，拒 VHT80

## 前置条件与拒载

- `USB` 未插（`/sys/class/extcon/USB/state` = 0）
- `di-camera-app` 未持有 `.MP4` 写 fd（录像中拒绝）
- 5 GHz 额外要求：CN 规范域只有两条规则（2402–2482 @40 MHz、5150–5250 @80 MHz indoor），
  wiphy 报告 5220/5240 均 `present && allowed`，否则拒

## 部署（尚未上机）

来源包：`NX_LUT_Lite_0.4.0_RC6.14.10_full.zip`（32.1 MB）
SHA256 `6cdd2626d570a68994e04af3b3fc5b4fa9d31a744b5ed01d888c8cf0ce311175`（已核对）

```sh
# 相机端目标：/opt/usr/nx-ks/wifi/
scp -r scripts/nx-rc/wifi/* root@<cam>:/opt/usr/nx-ks/wifi/
# 机端
chmod 755 /opt/usr/nx-ks/wifi/nxwifi.sh /opt/usr/nx-ks/wifi/bin/*
sh /opt/usr/nx-ks/wifi/nxwifi.sh status
```

`nxl-wifi-server` 是 **ELF32 ARM static（无 NEEDED）**，不依赖相机 glibc 2.13，可直接跑。
它自己 `mkdir /tmp/nx-lut-lite`，flock 只用于自身并发（`run.lock`），与我方 A18/P0 门控无关。
`nxl-wifi-radio` 里硬编码 `INSTALLED="/opt/usr/nx-lut-lite"`，只在 5 GHz 路径用到；
要跑 5 GHz 需 `ln -sfn /opt/usr/nx-ks/wifi /opt/usr/nx-lut-lite`，或改宏重编。

## 已知缺口

- **热点密码**读不到：原厂密码在 `di-camera-app` 的 preference 页（物理 `0x85480000+0x106e3`），
  用户态配置里没有。当前只报 SSID + `uap0` 地址；要出二维码必须补这一步
- `src/` 用我方 glibc-2.13 配方链接会断在 `__isoc23_*` / `fstat64` / `lstat64`（对方是 musl 静态）
- 尚未上机验证（`st app softap start` 会中断相机现有 STA 连接，必须在有人操作时做）
