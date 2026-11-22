# Reddit 文案 · Metol 1.15.9（2026-11-22）

适用版块：r/SamsungNX（主）、r/VintageDigitalCameras、r/cameras
Flair：DIY / Mod / Repair

---

**Title**

Metol 1.15.9 for NX500 — menu renamed, video settings unified into one page, and a LAN album so your phone can pull photos without an app

**Body**

This is a release of [Metol](https://github.com/WApaperplane/NX500-metol), an AGPL-3.0 mod for the
Samsung NX500 (firmware 1.12, DRIMe5). It's a fork of `ottokiksmaler/nx500_nx1_modding` plus the
`WApaperplane/metol` bloodline; it does not touch the firmware image, everything runs from the SD
card / `/opt/usr`.

**What's new in 1.15.9**

1. **Menu header finally says Metol.** It had been showing the old `NX-KS / Menu` for a year.

2. **New "Video" page.** Video settings used to be scattered between "Custom Func." and a separate
   resolution page. Now there's one page ordered resolution → bitrate → curve:
   - Resolution sub-page: `4K Full 24p`, `4K Native 30p`, `2.5K (2560×1440)`, `Crop 80% 30p`
   - Video bitrate (stock five presets)
   - V-Log curve
   - Batch recording

3. **Two ways to get photos off the camera**, both under Settings:
   - **LAN album** — tap it, the camera pops `http://192.168.x.x/` on screen. Phone on the same
     router opens it, full-size download included.
   - **Camera hotspot** — 5 GHz / 2.4 GHz / off. The camera becomes its own AP and pops its address
     on screen once it's up. Under the hood: band-enable word at `/dev/mem 0x85440068`, swap in a
     `cfg80211` module built for CN 5 GHz channels (insmod'd from `/tmp`, the on-disk module is
     untouched), then bind-mount over `/usr/sbin/hostapd` so the stock launch path gets our config
     (CH48 / HT40-minus).
     
     The one non-obvious prerequisite: the stock `mobileap-agent` has to be running, otherwise
     nothing ever calls `hostapd`. It's activated over the system bus via
     `org.tizen.tethering` — the service file sits in `/usr/share/dbus-1/services/` and
     `/etc/dbus-1/system.conf`'s `servicedir` points there. Any method call wakes it up, so the
     script just pings it before starting the hotspot. Took me a while to find that one.

**Status**

- LAN album: works.
- Camera hotspot (5 GHz and 2.4 GHz): works.
- 4K Full 24p: wider field of view than native UHD (full-width sensor readout), but the frame-drop
  problem is still open. I list it as research, not as a working 4K30. For stable video use
  `2.5K` or `4K Native 30p`.

**Install**

Download `Metol-1.15.9-EN.zip` from the release, extract to the SD card root, insert, the camera
says "install complete" and reboots. Keep a backup of your card and your original firmware. The SD
card's `scripts/` folder is the master copy — `cp -ar` only overwrites, it never deletes, so if you
edit files on the card, put the new ones there too or the next install reverts you.

**Credits**

AGPL-3.0, derived from `ottokiksmaler/nx500_nx1_modding` and `WApaperplane/metol`. The WiFi and
video-mode components in this release come from `NoireSchwarz/NX500_SRW_reprocessing_6.5K-oversampling`
(also AGPL-3.0, also derived from metol) — attribution is in `ATTRIBUTION.md`.

Release: https://github.com/WApaperplane/NX500-metol/releases/tag/v1.15.9
