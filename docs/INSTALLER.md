# Installer and boot-image flow

This document describes the **only supported install path** for the image. It
is a checklist; do not run the partition-writing steps until you have read
`README.md` and approved them.

## What the image contains

The `.img.xz` is a bare ext4 filesystem:

- label `LINUX70ROOT`;
- Ubuntu 26.04 GNOME rootfs;
- kernel modules in `/usr/lib/modules/7.0.14-dby-w09`;
- the blob-free boot bundle in `/usr/lib/matepad/linux-boot`:
  `Image.gz`, `sm8250-huawei-dby-w09.dtb`, `dtbo.img`,
  `ramdisk-payload.img`, `cmdline.txt`, `release.txt`, `SHA256SUMS`;
- the device-file **lists** in `/usr/share/matepad/device-files`.

It contains no Huawei firmware, no `boot.img`, no partition table and no
bootloader.

## What the installer does

The existing `dby-w09-installer` APK (HarmonyOS, root) performs:

1. **Card prep** — verifies the card, writes the ext4 image to the card
   partition, grows the filesystem.
2. **Device files** — copies the tablet's own vendor/firmware paths from
   `device-files/manifest.txt` and `firmware.txt` into the image:
   `/vendor`, `/system`, `/odm`, `/apex`, `/android-properties`,
   `a650_zap.*`, `adsp.*`, `slpi.*`, `venus.*`.
3. **Identity** — writes `/etc/matepad/wlan-mac`, `bt-mac`, `pen-mac`.
4. **Stock images** — saves the current `boot`, `ramdisk`, `dtbo` partitions
   under `/usr/local/share/matepad/harmonyos-images` with SHA256SUMS.
5. **Boot bundle** — verifies the bundle's SHA256SUMS and copies it to
   `/cache/linux70`.
6. **Account** — creates the requested user, sets the password, locale,
   keyboard, timezone, optional autologin and swap.
7. **Boot images** — builds the three partition images on the tablet:
   - `boot`: stock header v2 layout, kernel `Image.gz`, DBY DTB, cmdline;
   - `ramdisk`: stock partition with `ramdisk-payload.img` overlaid, keeping
     the AVB footer;
   - `dtbo`: `/rootparam` overlay packed by `pack_dtbo.py`.
   Each is written and read back; failure stops before reboot.
8. **Boot Linux** — writes the three images and reboots.

Huawei ABL refuses `fastboot boot`, so a RAM-only test is impossible. The
installer's readback check and the stock-image backups are the safety net.

## Host-side preflight

Before copying the image to the tablet:

```bash
cd dby-w09-ubuntu
./scripts/verify-image.sh
sha256sum -c build/out/ubuntu-26.04-gnome-dby-w09-20261111.img.xz.sha256
```

On the tablet (HarmonyOS, root), confirm the target card and backup:

```bash
adb shell su -c 'ls -l /dev/block/mmcblk1*'
adb shell su -c 'ls -l /dev/block/by-name/boot /dev/block/by-name/ramdisk /dev/block/by-name/dtbo'
```

Do **not** continue if the card is not the expected microSD, or if the
`edl/backup/20261109-133742/` images are missing/corrupt.

## Install

1. `adb push build/out/ubuntu-26.04-gnome-dby-w09-20261111.img.xz /sdcard/Download/`
2. Open **MatePad Linux** (installer APK) on HarmonyOS.
3. Choose **Image file**, select the `.img.xz`, select the microSD.
4. Fill in user/password/hostname/locale/keyboard/timezone/autologin.
5. **Install**; wait for the image write and device-file copy.
6. **Boot Linux**; the tablet reboots into the new rootfs.
7. First boot: GDM autologin is translated by
   `matepad-gdm-autologin.service`; if it fails, log in at GDM or the USB
   serial console.

## Return to HarmonyOS

From GNOME: **Restart to HarmonyOS** (uses the saved stock images), or from a
Linux serial/SSH shell:

```bash
sudo /usr/local/sbin/matepad-boot-harmonyos
```

From fastboot, the manually approved recovery is:

```bash
fastboot flash boot    boot.img
fastboot flash ramdisk ramdisk.img
fastboot flash dtbo    dtbo.img
fastboot reboot
```

using the files in `edl/backup/20261109-133742/`.

## Boot-image inspection (no writes)

The bundle is self-describing:

```bash
cd build/rootfs/usr/lib/matepad/linux-boot
sha256sum -c SHA256SUMS
cat release.txt
strings sm8250-huawei-dby-w09.dtb | grep -E 'dby-w09-panel|syh62758'
```

The DTB must contain both the panel node and the SYH62758 backlight node. If
either is missing, stop: the installer would build a boot image without
working display/backlight.

## Why there is no host-side `fastboot flash` helper

Writing `boot`, `ramdisk` or `dtbo` is a destructive operation with a
device-specific ABL contract. The installer already implements the verified
sequence, keeps the stock images, and checks readback. A generic host script
would duplicate it without the tablet's own stock layout and is intentionally
not provided. Host-side tools in this repository are read-only or produce
images only; they never write the tablet.
