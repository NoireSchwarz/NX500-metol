# Metol 1.15.7

发布日期：2026-11-20
这一版改的是**滤镜面板怎么放 V-Log 表**，外加一条把第三方 V-Log 创意表烘成可上机表的链路。

## 一、vlog 表不再单独占一个页签

上一版起，LUT 面板顶栏是 `● LUT │ FILMLAB │ 混合 │ 菜单 │ 关闭`。V-Log 表原本要再挤进
第三个页签，被否掉了 —— vlog 表和普通表写的是**同一个 A18 槽**，区别只是「这张表按哪种
输入域做的」，不是第二层。

现在的交互：

| 你在哪 | 点 LUT 页签的结果 |
|---|---|
| FilmLab 层 | 回到 LUT 层（域不变） |
| **已在 LUT 层** | **换域：标准表 ⇄ V-Log 表** |

页签文字跟着变：`● LUT` ↔ `● LUT·VLOG`。换域只重读一份清单，**不写 A18、不触发 DMA**
（真机点两次后 `BACKEND kind=1` 计数为 0），两个域各自记住停在哪张表。

顶栏宽度对调（LUT 132→152、FILMLAB 152→132）给 `● LUT·VLOG` 让位，总宽 284 不变。

## 二、Lumix V-Log 库导入链路

上游 [`changyun233/Lumix-V-log-LUTs`](https://github.com/changyun233/Lumix-V-log-LUTs)
（107 张 `.cube` + 25 个 `.vlt`），本版取了 `varicam_official` 35 张 + `lumix_color_lab` 22 张。

**关键约束**：上游表吃 **V-Log 编码**（18% 灰 = 0.42），而 A18 槽吃的是相机 ISP 输出的
显示参考流（JPEG 域，前面没有对数解码）。直接把 V-Log 表写进槽 = 双重错位 ⇒ 欠曝发灰。

所以走前置复合：

```
T_std(x) = T_vlog( S2V(x) )
```

`S2V` 是「Standard → V-Log」前向转换，烘完输出 33³ cube，再转成 19,712 B 的 17³ 槽表。
实测 `kodaP400` 的 18% 灰：原表 0.46→0.585，烘后 0.46→0.509 —— look 的意图保住了，
但 V-Log 表天然抬暗部的特性也一并搬了过来（0.18 输入 0.085→0.244），观感偏低对比，
属设计使然而非缺陷。

去重按 ΔE00（门槛 3.112），基准从仓库 `looks/` 的 89 张扩到**整库 125 张**：

| 域 | 候选 | 结果 |
|---|---|---|
| 标准域（S2V 烘焙后） | 57 | **56 DISTINCT**，1 张挡掉（`lcl_cinetone` vs `kodak_ektar100`，2.43） |
| V-Log 域（原表） | 57 | **57 DISTINCT**（只跟 `_vlog/` 现有 10 张比，最小 3.36） |

> V-Log 域去重只在**同域内**做。跟标准域那 125 张比会冒出 3 个"重复"
> （`vl_bw_locondk` ~ `mono_acros` 等），那是跨域伪重复 —— 同一张黑白表吃 log 和吃 JPEG
> 完全是两回事。

### 名字上限是 12 个字符

面板列表 5 格 × 133 px、19px 字体，**13 个字符起就被裁**（实测 `lcl_nostbleach` 显示成
`lcl_nostblea`）。批量导库前先按 12 字符过一遍。V-Log 域的副本一律加 `vl_` 前缀
（`vc_bleach_sb` → `vl_bleach_sb`）：`lut.sh` 取表时先查 `looks/`、查不到才查
`looks/_vlog/`，同名会永远命中标准版。

## 三、顺带修掉的三个既有缺陷

| 文件 | 问题 | 后果 |
|---|---|---|
| `nxui.c::services_visible()` | 仍按 2×3 时代的 `page*6` 算可见项 | 菜单第 7 项之后的服务开关**永远不刷新状态**，面板上 Telnet/FTP 标签卡死 |
| `verify_display.py` / `test_layers_2b.py` | 断言菜单页 `panel=720x336` | 3×4 网格改造后实际是 292，全套验证第一步就假失败 |
| 六个测试文件 | 写死宿主版 `out/test_input` | qemu/arm 目标下它会去加载相机 rootfs 的 ARM libX11 直接崩 ⇒ **arm 的点击测试从来没真正跑过** |

另外 `load_menu()` 失败现在会留一行 `MENU FAIL path|parse` 日志 —— 之前它只改面板上的
中文状态，测试与现场排障都看不到。

## 四、验证

| 项 | 结果 |
|---|---|
| 主机编译 + `test_model` / `test_services` | 通过 |
| `verify_display.py` host（含换域点击断言） | 11 项全 PASS |
| `verify_display.py` arm（qemu + 相机 ABI） | 10 项全 PASS |
| 真机渲染 `● LUT` / `● LUT·VLOG` | 720×208，页签不裁切，中文正常 |
| 真机点击页签两次 | `SCOPE vlog entries=10` → `SCOPE std entries=120 sel=9` |
| 上机后条目数 | 标准域 **176**（120+56）/ V-Log 域 **67**（10+57） |
| 表文件完整性 | 两批全量 md5 逐文件比对一致（56/56、57/57） |

## 五、升级注意

- **V-Log 域不是随时可用的**：那 57 张是原样 V-Log 输入，只有在 V-Log gamma 生效时才对。
  曲线引擎在机身 `$D/gamma/`，默认不随包安装；没有引擎时请用标准域。
- **本版不随包分发第三方 LUT**。`varicam_official` 属 Panasonic，其余属各作者；
  上游明确因版权建议从原链接获取。需要时按
  `docs/current/LUMIX_VLOG_IMPORT_2026-11-20.md` 自行烘一遍（脚本可重入）。
- 标准域 176 条 / V-Log 域 67 条是**开发机现状**，随包仍是定档集（`looks/MANIFEST.txt`）。

## 六、致谢

- **[NoireSchwarz/NX500_SRW_reprocessing_6.5K-oversampling](https://github.com/NoireSchwarz/NX500_SRW_reprocessing_6.5K-oversampling)**
  —— 在松下 V-Log ⇄ Standard 曲线上的研究与拟合。这一版能把 V-Log 创意表烘成「标准输入」
  的可上机表，前提就是那条曲线；没有它，107 张 V-Log 表在 NX500 上只能是一堆双重错位的灰片。
- **[changyun233/Lumix-V-log-LUTs](https://github.com/changyun233/Lumix-V-log-LUTs)**
  —— 107 张 V-Log 创意表的整理与预览（Booz / 尝云 / 翰博 / Lucas Hu / Lumix Color Lab /
  VariCam 官方）。
- **[ottokiksmaler/nx500_nx1_modding](https://github.com/ottokiksmaler/nx500_nx1_modding)**
  —— 血缘上游。
