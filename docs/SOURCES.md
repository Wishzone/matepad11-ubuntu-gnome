# Upstream sources used

Cloned by `scripts/fetch-upstream.sh` into `upstream/` (shallow, not vendored).

| Project | Commit at audit | Role |
| --- | --- | --- |
| [svesnav/linux-dby-w09](https://github.com/svesnav/linux-dby-w09) | `116cb1f` (2026-11-02) | Kernel 7.0.14 DBY-W09, DTB, panel/touch/audio/power patches, boot bundle tools |
| [svesnav/kubuntu-dby-w09](https://github.com/svesnav/kubuntu-dby-w09) | `da3db9f` (2026-11-02) | Hardware services, bare-ext4 image contract, device-files lists, KDE integration |
| [svesnav/dby-w09-installer](https://github.com/svesnav/dby-w09-installer) | `c58d804` (2026-11-02) | HarmonyOS installer APK, partition writes, user setup, boot switch |
| [armbian/build](https://github.com/armbian/build) | `ff5971b` (2026-11-11) | Resolute/desktop/mmdebstrap audit; not used for the boot chain |
| [linux-msm/hexagonrpc](https://github.com/linux-msm/hexagonrpc) | `da7a374` (2026-09-15) | SLPI sensor FastRPC server |

Local hardware evidence reused from the earlier bring-up:

- `../recovery/current-linux-boot/` — kernel/DTB/ramdisk payload bundle.
- `../recovery/current-modules-7.0.14-dby-w09.tar.gz` — modules.
- `../recovery/backlight/` — SYH62758 driver, DTB helper, DPMS follower.
- `../ubuntu/README.md` — the complete Kubuntu bring-up log (60 Hz touch root
  cause, panel variants, Wi-Fi/BT, battery, pen, camera, RTC).

Local kernel overlays and patches applied by this repository:

- `patches/0001-huawei-thp-lite-tabletmode-pen-rotation.patch` — tablet-mode
  switch and pen rotation.
- `patches/0003-huawei-thp-type-b-multitouch.patch` — Type-B slot reporting
  for stable Linux multitouch tracking IDs.
- `overrides/touchscreen/matepad-touch-rightclick.c` — GPL-2.0 touchscreen
  filter and pointer/scroll gesture bridge.

Things deliberately **not** taken from other devices:

- Xiaomi elish/pipa/dagu DTBs, DTBOs, boot images, firmware, partition layouts.
- Random “Ubuntu GSI” images.
- Any Huawei vendor file: the installer copies those from the user's tablet;
  this repository only stores path lists.
