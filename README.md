# Ubuntu 26.04 LTS + GNOME for the Huawei MatePad 11 (DBY-W09)

A clean, reproducible Ubuntu 26.04 LTS (Resolute Raccoon) ARM64 root file system
with GNOME 50, GDM on Wayland and the hardware support of the existing
[svesnav](https://github.com/svesnav/linux-dby-w09) DBY-W09 Linux port.

This repository does **not** contain Huawei firmware, bootloader images or
partition tables. The MatePad installer (`dby-w09-installer`) writes the root
file system to the microSD card and builds `boot`/`ramdisk`/`dtbo` from the
tablet's own stock images. Huawei's ABL requires that layout; it rejects
`fastboot boot`.

> **Status: milestone 3 — daily-driver build (2026-11-12).**
> GDM/GNOME Wayland, panel/backlight, freedreno GPU, touch, M-Pencil,
> Bluetooth keyboard (patched BlueZ), Wi-Fi, audio, sensors, auto-rotation
> (including with the magnetic keyboard), hardware RTC, both cameras,
> suspend/resume and charging have been exercised on the device. A touchscreen
> filter now maps one-finger input to a pointer and two-finger motion to scroll,
> suppressing native pinch; synthetic Type-A/Type-B tests pass, with physical
> verification pending. Boot to
> `graphical.target` is about 9 s. USB-C host/DP and a few minor items remain
> open — see [`docs/DEVICE-STATUS.md`](docs/DEVICE-STATUS.md) and
> [`docs/KNOWN-ISSUES.md`](docs/KNOWN-ISSUES.md).

## Artifact

The current validated rootfs image is generated locally at
`build/out-resume-fix/ubuntu-26.04-gnome-dby-w09-20261112.img.xz`; image files
are intentionally gitignored. Its checksum is recorded alongside it in the
`.sha256` file.

| Item | Value |
| --- | --- |
| Distribution | Ubuntu 26.04.1 LTS (Resolute), arm64 |
| Desktop | GNOME Shell 50.1, GDM 50.1, Wayland |
| Kernel | Linux 7.0.14-dby-w09 (from the existing port) |
| Mesa / Vulkan | 26.0.8, freedreno (Adreno 650) |
| Audio / session | PipeWire 1.6.2, WirePlumber 0.5.13 |
| Image | bare ext4, label `LINUX70ROOT`, no partition table |
| Uncompressed size | 6,302,232,576 bytes (about 5.87 GiB) |
| `.img.xz` SHA-256 | `ba970b27fd1583f5d0fc44d135aaedba85951a0a0509a419c1b61495b3ea959b` |
| `.img.xz` size | 1,252,021,360 bytes (about 1.17 GiB) |
| Boot bundle (2026-11-12) | `boot-kernel-penrot-20261112.img`, SHA-256 `91556d3f249b7d32466c30795a2de45bd4cc0bf13a6743e926bf0557e1ff9789` |

## Releases

Rootfs images and boot bundles are too large for git. Publish them as GitHub
Release assets; `releases/<date>/MANIFEST.json` records the hashes, the
kernel/DTB revisions and what was verified. The repository itself contains
only source, configuration and patches.

## Repository layout

- `configs/` — package list, rootfs build scripts, GNOME first-login setup.
- `scripts/` — fetch, patch, rootfs and image build scripts.
- `overrides/` — BlueZ HOG patch, UPower sign shim, SYH62758 backlight driver, touchscreen gesture filter, GNOME flashlight toggle.
- `patches/` — kernel touch/pen, camera, audio and DTB patches with notes.
- `upstream.lock` — pinned commits of the four upstream repositories.
- `docs/` — architecture, build, device status, known issues, hardware notes.
- `build/`, `tools/` and `upstream/` are generated locally and gitignored.

The bare ext4 image is intentional: the installer writes it to the card's first
partition (or grows it), then copies the tablet's firmware and vendor files into
it. A disk image with a partition table would duplicate the installer's job and
would still not provide a Huawei-compatible `boot` image.

## What is inside

- A real Ubuntu 26.04 arm64 userland built from the Resolute archive — not a
  Kubuntu/24.04 upgrade with KDE removed.
- `ubuntu-desktop-minimal`, `ubuntu-session`, `gnome-shell`, `gdm3`,
  `gnome-control-center`, `nautilus`, `gnome-terminal`, Ubuntu Dock/Yaru.
- NetworkManager, wpa_supplicant, BlueZ, OpenSSH, PipeWire/WirePlumber, Mesa
  freedreno, Vulkan, linux-firmware (Qualcomm graphics/wireless/misc split
  packages).
- The DBY kernel modules and the blob-free boot bundle
  (`/usr/lib/matepad/linux-boot`), so the installer can build the three boot
  partitions without downloading anything.
- The device-support pieces from `kubuntu-dby-w09` that are desktop-agnostic:
  binderfs touch bridge plus filtered touchscreen gestures, sensors
  (`hexagonrpcd`), speaker amplifier service,
  volume keys, charging LED, M-Pencil helpers, USB-C/DP recovery, flashlight
  (desktop action and a GNOME quick-settings toggle), and “Restart to HarmonyOS”.
- This tablet's **SYH62758** backlight driver (`syh62758_bl.ko`) and DTB node,
  plus the DTB panel rotation (portrait 1600×2560 → landscape for GNOME).
- GNOME-specific integration: GDM autologin translation from the installer's
  SDDM setting, first-login scaling/on-screen-keyboard/input-source setup.

It deliberately does **not** contain: KDE Plasma, SDDM, KScreen, KWin,
`plasma-desktop`, the Maliit/Plasma on-screen keyboard, the KDE battery applet,
or `snapd`.

## Build

The build is rootless: it uses a user namespace, `binfmt_misc` and a static
`qemu-aarch64` (or proot on hosts where bind mounts are restricted). See
[`docs/BUILD.md`](docs/BUILD.md) for the full requirements and the exact
commands. Short version:

```bash
cd dby-w09-ubuntu
./scripts/prepare-host-tools.sh
./scripts/build-rootfs.sh --from-scratch \
    --bundle ../recovery/current-linux-boot \
    --modules ../recovery/current-modules-7.0.14-dby-w09.tar.gz
./scripts/make-image.sh
```

`scripts/build-rootfs.sh` performs:

1. `debootstrap --foreign` of Resolute arm64 (no ARM execution yet).
2. second stage through a rootless chroot with `qemu-aarch64-static` and
   `binfmt_misc`;
3. the GNOME package set, with `fakeroot` faking the package ownership that a
   non-root build cannot write;
4. compiling the small C helpers and `hexagonrpcd`;
5. staging the hardware services and the GNOME integration;
6. final userspace configuration and `depmod`.

`scripts/make-image.sh` applies the real package ownership to the tree under
`fakeroot`, runs `mke2fs -d`, shrinks/grows the image and verifies key modes
with `debugfs` before creating the `.img.xz`.

## Install (not automated here)

The supported route is the existing **MatePad Linux installer** APK on
HarmonyOS, with a microSD card; it preserves HarmonyOS on internal storage.
The exact flow, what the installer writes and the readback checks are in
[`docs/INSTALLER.md`](docs/INSTALLER.md):

1. Bootloader unlocked, HarmonyOS rooted (APatch/Magisk), microSD inserted.
2. Copy the `.img.xz` to the tablet, open the installer, choose **Image file**,
   select the card, set user/locale/keyboard/timezone, install.
3. **Boot Linux** in the installer. It writes `boot`, `ramdisk`, `dtbo` from
   the tablet's stock images plus the bundle in the image, verifies readback,
   and reboots.
4. Return to HarmonyOS with **Restart to HarmonyOS** or by restoring the three
   stock images from `edl/backup/20261109-133742/`.

**Do not run `fastboot flash`, `fastboot erase`, `mkfs` or `dd` on a real
partition without an explicit, separate approval.** The image itself only
contains a userland; the installer and ABL do the only partition writes.

## Repository layout

```text
configs/apt/            Ubuntu Resolute apt source
configs/rootfs/         GNOME/GDM/first-login integration and finalization
docs/                   architecture, build, testing, compatibility, issues
overrides/backlight/    SYH62758 driver source + module + DPMS follower
overrides/touchscreen/  multitouch filter, pointer emulation, gesture service
overrides/bluez/        BlueZ 5.85 HOG patch + patched arm64 debs
overrides/upower/       UPower current-sign compatibility shim
overrides/flashlight/   GNOME quick settings toggle for the rear flash
patches/                kernel touch/pen, camera, audio and DTB patches
scripts/                host tools, rootfs build, DTB patch, image build, tests
upstream/               shallow clones used for source audit (not vendored)
build/                  generated rootfs/image/logs (git-ignored)
```

## Hardware support

See [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md). The short version:

| Area | State in this image |
| --- | --- |
| Display / panel | 60 Hz 190_20d kernel; DTB rotation 90; SYH62758 backlight; **verified on device** |
| GPU | Mesa freedreno FD650 + Vulkan; **verified on device** |
| Touch / pen | Finger and M-Pencil follow rotation in all four orientations; kernel tablet-mode switch; **verified on device** |
| Touch gestures | Filtered single-pointer/two-finger scroll/right-click; virtual Type-A/Type-B tests pass, physical retest pending |
| Wi-Fi / BT | Wi-Fi associated; BlueZ keyboard/M-Pencil paired; **verified on device** |
| Audio | TFA9874 service + UCM2 + PipeWire; WirePlumber 0.5 speaker rules **not ported** |
| Sensors / rotation | `hexagonrpcd` + `matepad-sensord`; auto-rotate works in tablet mode; **verified on device** |
| Battery / charging | UPower + direct charger `Charging`; LED; **verified on device** |
| Suspend | SLPI/FastRPC stop-start hook; RTC wake tested without a sensor DSP crash |
| Camera | front GC8054 (GRBG) + rear OV13B10 via libcamera/PipeWire; **verified on device** |
| RTC | SDAM RTC offset in the boot DTB; `hwclock -w` persists; **verified on device** |

## Safety and recovery

- Every partition the installer writes (`boot`, `ramdisk`, `dtbo`) was backed up
  before the first install in `edl/backup/20261109-133742/`.
- Huawei ABL refuses `fastboot boot`; a RAM-only test is not possible.
- The image never writes a partition table and never touches internal storage.
- If a boot test fails, restore the three stock images from fastboot:

  ```bash
  fastboot flash boot    boot.img
  fastboot flash ramdisk ramdisk.img
  fastboot flash dtbo    dtbo.img
  fastboot reboot
  ```

- Do not mix Xiaomi elish/pipa/dagu DTBs, firmware or boot images with this
  device. They are different boards.

## License

Project scripts and documentation: MIT (see `LICENSE`). The kernel, device tree
and backlight driver are GPL-2.0-only; the upstream DBY-W09 userspace helpers
retain their own licenses. See `NOTICE` and the upstream repositories.
