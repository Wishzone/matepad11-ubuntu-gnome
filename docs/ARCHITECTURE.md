# Architecture and source audit

## 1. Why a hybrid Armbian/MatePad build

The requested first choice was the Armbian Build Framework. The framework was
audited from a current clone (commit `ff5971b`, 2026-11-11):

- It does support Ubuntu 26.04 as a target:
  `upstream/build/config/distributions/resolute/name` is `Ubuntu resolute 26.04`.
- Its rootfs stage already uses `mmdebstrap`
  (`upstream/build/lib/functions/rootfs/rootfs-create.sh`).
- Desktops are no longer a simple package list in the board config; the
  framework fetches `armbian/configng` and installs a desktop through
  armbian-config modules (`upstream/build/lib/functions/configuration/config-desktop.sh`).

But Armbian's image path assumes a board boot chain it controls (U-Boot/SPL,
extlinux/boot.scr, Armbian board config, partition layout). The DBY-W09 is not
one of its boards and Huawei's ABL imposes a different contract:

- `boot` is an Android header v2 image whose ramdisk is **separate** on the
  `ramdisk` partition.
- ABL applies a DTBO that must populate `/rootparam`, or it returns to fastboot.
- `fastboot boot` (RAM-only boot) is refused by this ABL.
- The root is a bare ext4 filesystem labelled `LINUX70ROOT` on the microSD; the
  existing installer writes it into the card and creates the boot partitions
  from the tablet's own stock images.

Therefore this project uses the hybrid architecture explicitly allowed by the
task:

```text
Ubuntu 26.04 arm64 + GNOME   debootstrap/mmdebstrap-compatible rootfs
        |
        +-- kernel/modules   existing linux-dby-w09 7.0.14 bundle
        +-- hardware layer   kubuntu-dby-w09 system services (no KDE)
        +-- boot assembly    dby-w09 installer / ABL header-v2 bundle
        +-- rootfs image     bare ext4, LINUX70ROOT, installer-written
```

This keeps the valuable parts of Armbian's approach (Resolute archive,
mmdebstrap/debootstrap rootfs, repeatable package selection) without pretending
that an Armbian U-Boot image can boot a Huawei ABL device.

## 2. Boot flow

1. HarmonyOS is rooted; the installer APK runs as root.
2. It writes the ext4 image to the microSD partition and grows it.
3. It copies the tablet's own firmware/vendor files into
   `/usr/lib/firmware/qcom/sm8250/huawei/dby-w09` etc.
4. It saves the stock `boot`, `ramdisk`, `dtbo` partitions.
5. It builds:
   - `boot`: stock header v2 + Linux `Image.gz` + DBY DTB + cmdline;
   - `ramdisk`: stock partition with `ramdisk-payload.img` overlaid (AVB footer
     preserved);
   - `dtbo`: `dby-w09-rootparam.dtso` packed by `pack_dtbo.py`.
6. ABL boots the kernel; the initramfs mounts the ext4 root by label.
7. To return: `matepad-boot-harmonyos` writes the stock images back, or fastboot
   restores them from the backup.

No Huawei file is redistributed by this project. The image contains only the
device-files **lists**; the installer copies the actual files from the tablet.

## 3. Rootfs build

- Base: `debootstrap --foreign --variant=minbase` for `resolute` arm64, then a
  second stage through `proot` + `qemu-aarch64-static` (proot intercepts the
  chown calls made by debootstrap's base-package maintainer scripts), and a
  rootless chroot with `binfmt_misc` for the later configuration.
- Package set: `ubuntu-desktop-minimal` + explicit GNOME/GDM/NetworkManager/
  PipeWire/Mesa/firmware/tools; no `snapd`, no KDE.
- Ownership: the host is not root. Package extraction runs as fake root in a
  user namespace; `fakeroot` (with `FAKEROOTDONTTRYCHOWN=1`) records the
  intended uid/gid. `mke2fs -d` runs under the same fakeroot daemon, so the
  ext4 inodes get real ownership. A manifest generated from the cached `.deb`
  metadata and `dpkg-statoverride` is applied first; this is what preserves
  `4755` sudo/passwd/pkexec, `2755 root:_ssh` ssh-agent, `4754
  root:messagebus` dbus-daemon-launch-helper, `root:shadow` `/etc/shadow`, etc.
- The image is a bare ext4 filesystem, not a partitioned disk image.

## 4. Kernel and device tree

- Kernel: 7.0.14-dby-w09, built from `svesnav/linux-dby-w09` with this tablet's
  190_20d panel and 60 Hz touch fix. The current boot bundle is reused from
  `recovery/current-linux-boot`; a clean rebuild is documented in
  `docs/BUILD.md`.
- The DTB is patched by `scripts/patch-dtb.sh`:
  - `rotation = <90>` on `panel@0` (Mutter panel orientation);
  - `backlight@2e` with `syh,syh62758`, because this unit uses SYH62758 at
    i2c-11 0x2e, not the RT8555 at 0x31 in the upstream default DTB.
- `syh62758_bl.ko` is built for exactly `7.0.14-dby-w09` and loaded by
  `matepad-modules.service`; `matepad-panelbacklightd` follows DSI DPMS.
- The environment deliberately does not update the kernel via apt. The kernel
  and modules are shipped as files; `linux-image-dby-w09` should be held if a
  future image installs the Debian package.

## 5. Userspace hardware layer

The upstream `kubuntu-dby-w09` repository mixes desktop-independent services
with KDE integration. The split used here:

| Kept (system-level) | Excluded (KDE-only) |
| --- | --- |
| `linux70-touch` / binderfs bridge; `matepad-touch-rightclick` filtered pointer/gesture bridge | KScreen auto-rotation, `kscreen-dsi1-autorotate.json` |
| `hexagonrpcd` + `matepad-sensord` | Plasma battery applet |
| TFA9874 service, UCM2, PipeWire filter-chain | KWin/Qt Wayland patch, `kwinrc` |
| volume keys, charging LED, flashlight | SDDM config, Plasma session |
| M-Pencil BlueZ helpers | Maliit/Plasma on-screen keyboard, tray relayout |
| USB-C DP recovery, HDMI audio, DDC rules | `fix_docked_rotation.py` (KScreen-specific) |
| Restart to HarmonyOS | `plasmashell` guard, KDE autostart |
| device-setup / firmware lists | |

GNOME-specific replacements are in `configs/rootfs/`:

- `matepad-gdm-autologin`: converts the installer's SDDM autologin file into
  GDM's `custom.conf` before `gdm.service`.
- `matepad-gnome-user-setup`: first-login GSettings for scaling (1.5 text,
  2× integer fallback), GNOME OSK, input sources from `/etc/default/keyboard`,
  hot corners off, battery percentage.
- `matepad-boot-harmonyos-gui`: zenity-based launcher (the upstream GUI used
  kdialog).
- `enable-services.sh`: enables GDM, NetworkManager, BlueZ, SSH, timesyncd and
  the MatePad units from inside the chroot.

## 6. Known architectural gaps

- WirePlumber 0.4 Lua rules from Kubuntu do not load in WirePlumber 0.5. The
  files are staged for reference under `/usr/share/matepad/wireplumber-0.4`;
  the SPA-JSON port remains.
- The BlueZ HOG CCC-read patch is not applied to Resolute's BlueZ 5.85.
- The upstream suspend script is KDE/KWin/kscreen-doctor-specific and was not
  copied. GNOME/logind defaults are used.
- The camera userspace (libcamera with the MatePad gain models) is not in this
  milestone; only kernel drivers and device-access rules are present.
- The installer APK is not modified. Its KDE-specific user config files
  (`plasma-localerc`, `kxkbrc`, SDDM autologin) are harmless or translated;
  the GNOME user service imports the keyboard layout.

## 7. Source references

- `upstream/linux-dby-w09/README.md`, `configure-and-build.sh`,
  `build_release.sh`, `sd_root_init.sh`, `dby-w09-rootparam.dtso`.
- `upstream/kubuntu-dby-w09/packaging/stage-matepad.sh` — system services and
  KDE-specific files, split in `scripts/stage-hardware.sh`.
- `upstream/kubuntu-dby-w09/image/build-image.sh`, `chroot-setup.sh` — the
  original bare-ext4/installer contract.
- `upstream/dby-w09-installer/app/src/main/assets/matepad.sh` — partition
  writes, device-file copy, user/locale setup.
- `upstream/build/config/distributions/resolute/name`,
  `upstream/build/lib/functions/rootfs/rootfs-create.sh`,
  `upstream/build/lib/functions/configuration/config-desktop.sh` — Armbian
  audit.
- `recovery/backlight/README.md`, `recovery/backlight/syh62758_bl.c` — this
  tablet's backlight hardware and the verified sysfs interface.
- `docs/HARDWARE-NOTES.md` and the earlier Kubuntu hardware
  bring-up log (touch 60 Hz root cause, Wi-Fi/Bluetooth, battery, pen, camera,
  RTC).
