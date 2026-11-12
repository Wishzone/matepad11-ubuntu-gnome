# Armbian audit and hybrid integration

The task asked to prefer Armbian Build Framework. This is the audit result and
why the delivered build is a hybrid rather than an Armbian board image.

## What Armbian already has

From `upstream/build` (commit `ff5971b`, 2026-11-11):

- `config/distributions/resolute/name`: `Ubuntu resolute 26.04`.
- `lib/functions/rootfs/rootfs-create.sh`: rootfs creation through
  `mmdebstrap`, with package aggregation, apt cache hooks and qemu deployment
  (`deploy_qemu_binary_to_chroot`).
- `lib/functions/configuration/config-desktop.sh`: desktop selection is
  delegated to `armbian/configng` YAML modules (GNOME is one of the choices),
  not a static package list in the board file.
- `lib/functions/image/rootfs-to-image.sh`: Armbian's image/partition layout.

So the **rootfs side** is suitable and could replace the debootstrap pipeline.
The **boot side** is not.

## Why an Armbian board image cannot boot this tablet

- Armbian board configs describe U-Boot/SPL, `boot.scr`/extlinux and Armbian's
  own partition layout. DBY-W09 has no mainline U-Boot port and Huawei ABL
  refuses the generic boot flow.
- ABL requires an Android header v2 `boot` image, a separate `ramdisk`
  partition and a DTBO that fills `/rootparam`. Armbian does not generate that.
- `fastboot boot` is rejected, so there is no RAM-only fallback.
- The only known-working boot path is the existing MatePad installer, which
  builds the three images from the tablet's own stock partitions.

## Delivered hybrid

| Layer | Source |
| --- | --- |
| Ubuntu 26.04 arm64 base | debootstrap from the Resolute archive (same archive Armbian uses) |
| GNOME/GDM package set | explicit `configs/packages.list` (no snapd/KDE) |
| Kernel/modules/DTB | existing `linux-dby-w09` 7.0.14 bundle |
| Hardware services | `kubuntu-dby-w09`, split into system vs KDE |
| Rootfs image | bare ext4 `LINUX70ROOT`, installer contract |
| Boot images | `dby-w09-installer` + `pack-rootparam` DTBO |

The build is rootless and does not need Armbian's loop devices, U-Boot or
partition tools. It is therefore easier to reproduce on a workstation/CI than
an Armbian board build.

## If Armbian integration is desired later

A future `huawei-dby-w09.csc` board config would need:

- `BOARDFAMILY` for SM8250 (or a custom family), `BOOTCONFIG=none`;
- a rootfs-only build path (`KERNEL_ONLY=no`, no U-Boot, no Armbian partition
  table) that outputs the same bare ext4 image;
- a post-build hook that writes the MatePad boot bundle and `device-files`
  lists into the rootfs;
- the installer, not Armbian's `rootfs-to-image.sh`, for the boot partitions;
- a GNOME desktop module from `armbian/configng` pinned to the Resolute
  release.

This would reuse Armbian's cache/CI but still require the Huawei boot hook.
It is not claimed as tested here.
