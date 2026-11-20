# Metol 1.15.7

Released: 2026-11-20
This release changes **how the filter panel holds V-Log tables**, plus a pipeline that bakes
third-party V-Log creative LUTs into tables the camera can actually use.

## 1. V-Log tables no longer get their own tab

Since the previous release the LUT panel top bar reads `● LUT │ FILMLAB │ Mix │ Menu │ Close`.
Adding a third tab for V-Log tables was rejected — a vlog table and a normal table write the
**same A18 slot**; they differ only in *which input domain the table was built for*. It is not
a second layer.

| Where you are | What tapping the LUT tab does |
|---|---|
| FilmLab layer | Returns to the LUT layer (domain unchanged) |
| **Already on the LUT layer** | **Flips the domain: standard ⇄ V-Log** |

The tab label follows: `● LUT` ↔ `● LUT·VLOG`. Flipping only reloads one list — it does **not**
write A18 or trigger a DMA (measured: `BACKEND kind=1` count stays 0 after two taps), and each
domain remembers its own last selection.

Tab widths were swapped (LUT 132→152, FILMLAB 152→132) to fit `● LUT·VLOG`; the total stays 284.

## 2. Lumix V-Log library pipeline

Upstream [`changyun233/Lumix-V-log-LUTs`](https://github.com/changyun233/Lumix-V-log-LUTs)
(107 `.cube` + 25 `.vlt`). This release takes `varicam_official` (35) and `lumix_color_lab` (22).

**The constraint**: upstream tables expect **V-Log encoded** input (18% grey = 0.42), while the
A18 slot sits on the camera's display-referred ISP output (JPEG domain, no log decode in front).
Writing a V-Log table straight into the slot is a double mismatch ⇒ underexposed and washed out.

So they are pre-composited:

```
T_std(x) = T_vlog( S2V(x) )
```

`S2V` is the forward Standard→V-Log transform; the result is baked at 33³ and converted to the
19,712 B / 17³ slot table. Measured on `kodaP400` at 18% grey: 0.46→0.585 as a V-Log table,
0.46→0.509 after baking — the look's intent survives, but the shadow lift inherent to V-Log
tables comes along (0.18 input: 0.085 → 0.244), so contrast reads slightly lower by design.

Dedup uses ΔE00 (threshold 3.112) against the **whole library (125 tables)**, not just the 89 in
`looks/`:

| Domain | Candidates | Result |
|---|---|---|
| Standard (after S2V) | 57 | **56 DISTINCT**, 1 rejected (`lcl_cinetone` vs `kodak_ektar100`, 2.43) |
| V-Log (raw tables) | 57 | **57 DISTINCT** (compared only against the 10 existing `_vlog/` tables, min 3.36) |

> V-Log dedup is done **within its own domain**. Comparing against the 125 standard tables
> reports three "duplicates" (`vl_bw_locondk` ~ `mono_acros` etc.) — those are cross-domain
> artefacts; the same mono table fed log or JPEG is a different table entirely.

### 12-character name limit

The list row is 5 cells × 133 px at 19 px type — **names are clipped from 13 characters**
(`lcl_nostbleach` renders as `lcl_nostblea`, measured). Keep imported names ≤ 12 characters.
V-Log copies always get a `vl_` prefix (`vc_bleach_sb` → `vl_bleach_sb`): `lut.sh` resolves
`looks/` first and only falls back to `looks/_vlog/`, so an identical name would always hit the
standard table.

## 3. Three pre-existing defects fixed along the way

| File | Issue | Effect |
|---|---|---|
| `nxui.c::services_visible()` | still used the 2×3-era `page*6` window | service toggles **past item 7 never refreshed**, the Telnet/FTP label froze on screen |
| `verify_display.py` / `test_layers_2b.py` | asserted the menu page at `panel=720x336` | the 3×4 grid made it 292; the whole verification suite failed at step one |
| six test files | hard-coded the host `out/test_input` | under qemu/arm it loaded the camera rootfs ARM libX11 and died ⇒ **arm click tests had never actually run** |

`load_menu()` now logs a `MENU FAIL path|parse` line on failure — previously it only changed the
on-panel Chinese status, invisible to tests and field debugging.

## 4. Verification

| Item | Result |
|---|---|
| Host build + `test_model` / `test_services` | pass |
| `verify_display.py` host (now includes the domain-flip tap) | 11/11 PASS |
| `verify_display.py` arm (qemu + camera ABI) | 10/10 PASS |
| On-body render of `● LUT` / `● LUT·VLOG` | 720×208, tabs not clipped, CJK correct |
| Two taps on the body | `SCOPE vlog entries=10` → `SCOPE std entries=120 sel=9` |
| Table counts after deploy | standard **176** (120+56) / V-Log **67** (10+57) |
| File integrity | full md5 comparison, 56/56 and 57/57 identical |

## 5. Upgrade notes

- **The V-Log domain is not always usable**: those 57 tables are raw V-Log input and only make
  sense while V-Log gamma is active. The curve engine lives in `$D/gamma/` on the body and is
  not bundled; without it, use the standard domain.
- **No third-party LUTs ship in this release.** `varicam_official` belongs to Panasonic and the
  rest to their respective authors; upstream explicitly asks for the original links due to
  copyright. Bake your own set with `docs/current/LUMIX_VLOG_IMPORT_2026-11-20.md` (the script is
  re-entrant).
- 176 standard / 67 V-Log is the **dev body's** state; the package still ships the frozen set
  listed in `looks/MANIFEST.txt`.

## 6. Credits

- **[NoireSchwarz/NX500_SRW_reprocessing_6.5K-oversampling](https://github.com/NoireSchwarz/NX500_SRW_reprocessing_6.5K-oversampling)**
  — research and fitting of the Panasonic V-Log ⇄ Standard curves. Baking V-Log creative tables
  into standard-input tables only works because that curve exists; without it, all 107 V-Log
  tables would be nothing but double-mismatched grey on the NX500.
- **[changyun233/Lumix-V-log-LUTs](https://github.com/changyun233/Lumix-V-log-LUTs)**
  — curation and previews of the 107 V-Log creative tables (Booz / Changyun / Hamburger /
  Lucas Hu / Lumix Color Lab / VariCam official).
- **[ottokiksmaler/nx500_nx1_modding](https://github.com/ottokiksmaler/nx500_nx1_modding)**
  — upstream bloodline.
