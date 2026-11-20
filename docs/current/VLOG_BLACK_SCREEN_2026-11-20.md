# V-Log 录像黑屏 / 菜单"不可用"：根因与恢复（2026-11-20）

> 症状：开 V-Log 后录像 → 取景黑屏；此后主菜单里的「V-Log 开关 / 回原厂」
> 按了没反应（"不可用"）；重启也不一定回来。

## 1. 黑屏不是"效果不对"，是三个状态互相打架

事故现场（`/tmp/nx-lut-lite` 全量取证）：

| 层 | 实际值 | 应该是 |
|---|---|---|
| `clean-log.policy` | `NXL_CLEAN_LOG1 READY` | 没开 log 时应**不存在** |
| A18 槽（`0x81119F00`） | md5 `235ad453…` | 原厂 `4c0cc78c…`（= `session/a18_orig.bin`） |
| `session/video_enabled` | 存在 | 只应在"视频试用"期间存在 |
| DYN24（24 条视频选择器） | **24 条全 = `0x81119f00`** | 24 个各不相同的原厂地址 |
| gamma | `mode=FACTORY phase=OFF` | 与 policy 不一致 |

DYN24 是录像通路的表选择器。`log_neutral` 末尾的 `video_enable()`
（`nx_regtabwrite.arm dyn-write 0x81119F00`）把**整张 24 条表重指到 A18** ——
RC5 自己的日志也写了 `OK VIDEO_TRIAL_ON; start a NEW recording to test`。
A18 里此时是 log 的参考表（4913×4B 的 3D 表），而 DYN24 原本各是 1D 曲线，
形状对不上 ⇒ 录像启流时读空 ⇒ 黑屏。

RC5 的 JSON 自己就承认没验证过这条路：
`actual_new_video_consumption_verified:false`、`native_queue_is_hardware_completion:false`、
`hardware_pixels_verified:false`。

## 2. 为什么菜单里"不可用"

`vlog.sh toggle` 见到 `clean-log.policy` 就只走 `restore`，而 `restore` 死在这里：

```
reason=VIDEO_AUDIT_DIRECTORY_FAILED
```

`nxl-gamma-reload.arm` 往 `/mnt/mmc/NXDEMO51/` 写审计文件（二进制里写死
`"/mnt/mmc/NXDEMO51/GAMMA_R11Q_%llu_%d_%08x"`），而这个目录**默认不存在**。
于是 restore 直接退出，半状态原地留下 —— 之后每一次 toggle/off 都死在同一处，
表现为"按钮没反应"。

## 3. 恢复（黑屏时 ssh 里照抄）

```sh
mkdir -p /mnt/mmc/NXDEMO51                                   # 补审计目录
/opt/usr/nx-ks/gamma/bin/nx_regtabwrite.arm dyn-restore      # 视频选择器回 24 条原厂
/opt/usr/nx-ks/vlog.sh off                                   # A18 回 a18_orig + 清 policy
FILMLAB_PW=1 /opt/usr/nx-ks/filmlab.sh neutral               # PW 归中性（V-Log 前置）
/opt/usr/nx-ks/preflight.sh vlog                             # 应当 READY=1
```

实测恢复结果：A18 = `4c0cc78c…`（与 `a18_orig.bin` 逐字节相同）、policy 消失、
`video_enabled` 消失、DYN24 回到 24 个不同地址、`dyn-restore` 报 `READBACK ok`、
preflight `READY=1`。

## 4. 已做的硬化

| 改动 | 作用 |
|---|---|
| `vlog.sh::ensure_run` 同时 `mkdir -p /mnt/mmc/NXDEMO51` | restore 不会再因缺审计目录半途死掉 |
| 新增 `vlog.sh video-off` | 单独还原 DYN24，不碰 gamma/A18 —— 黑屏时的最小自救 |
| `restore` 成功后再查 `session/video_enabled`，残留就补一次 `dyn-restore` | 防"policy 没了但指针还指着 A18" |
| `vlog.sh on/toggle` 前检查 `tc.sh status` = `custom` 就拒绝 | TC 曲线与 V-Log 改同一条 gamma，不能叠 |
| `tc.sh set <非stock>` 前检查 `clean-log.policy` 就拒绝 | 反向互斥 |

实测：`tc.sh set log` → `vlog.sh on` → `BLOCKED=TC_CURVE_CUSTOM`；`tc.sh off` 回 `CURVE=stock`。

## 5. 仍未解决

- **V-Log 录像本身仍然不成立**。上面只是把状态救回来，`video_enable` 那条
  "24 条全指 A18"的路没有改。要真让录像带 log，得先弄清 DYN24 的 24 条
  各对应什么（哪些视频档、表长/格式），再决定是"只指其中几条"还是"给视频
  单独生成 1D 曲线"。这是 p7 侧的活。
- 在此之前，V-Log 只当**拍照/取景**用；要录像先 `vlog.sh off`。
- `lut.sh video-off` 在 VLOG 模式下救不了：lut-core 的分支让它走 `log_neutral`，
  末尾又 `video_enable`。必须用 `vlog.sh video-off`（直接调 dyn-restore）。
