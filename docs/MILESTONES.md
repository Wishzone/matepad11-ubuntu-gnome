# Milestones

## M0 — source audit and architecture (complete, 2026-11-11)

- Cloned and read `svesnav/linux-dby-w09`, `svesnav/kubuntu-dby-w09`,
  `svesnav/dby-w09-installer`, `armbian/build`, `linux-msm/hexagonrpc`.
- Confirmed Armbian supports Resolute rootfs but not the Huawei ABL boot chain;
  chose the hybrid rootfs + installer/boot-bundle architecture.
- Audited the existing tablet bring-up log (`../ubuntu/README.md`): 190_20d
  panel, 60 Hz touch fix, SYH62758 backlight, Wi-Fi/BT, battery, pen, camera,
  RTC.
- Output: `docs/ARCHITECTURE.md`, `docs/COMPATIBILITY.md`.

## M1 — clean Ubuntu 26.04 GNOME rootfs and image (complete, 2026-11-11)

- Rootless debootstrap of Resolute arm64; second stage through qemu-aarch64 in
  a user namespace.
- GNOME Shell 50.1 / GDM 50.1 / ubuntu-session; no KDE, no snapd.
- Mesa 26.0.8, PipeWire 1.6.2, WirePlumber 0.5.13, NetworkManager, BlueZ,
  OpenSSH, Qualcomm firmware split packages.
- Kernel 7.0.14-dby-w09 modules + boot bundle; DTB rotation 90; SYH62758
  backlight module/node; hardware services split from KDE.
- Bare ext4 `LINUX70ROOT` image with package ownership restored under
  fakeroot; `verify-image.sh` passes.
- QEMU boot with the DBY kernel reaches `multi-user.target`, login prompt, no
  failed unit.
- A clean run of `scripts/build-rootfs.sh --from-scratch` completed end to end
  (`build/logs/build-rootfs-clean2.log`), and its image passed
  `scripts/verify-image.sh` and `scripts/test-qemu.sh`.
- Artifact: `build/out/ubuntu-26.04-gnome-dby-w09-20261111.img.xz`.

**Evidence**

```text
Welcome to Ubuntu 26.04.1 LTS!
...
Ubuntu 26.04.1 LTS matepad ttyAMA0
matepad login:
```

`scripts/verify-image.sh` output: `PASS` (label, 26.04, GNOME/GDM, boot bundle,
SYH62758 module, hexagonrpcd, sudo/passwd/pkexec 4755, ssh-agent 2755
root:_ssh, dbus helper 4754 root:messagebus, shadow 0640 root:shadow, no
qemu/fakeroot leftovers, no KDE/snapd).

## M2 — first real-device boot (complete, 2026-11-11)

- Installed the image to the 128 GB microSD with the existing installer.
- Booted into GDM/GNOME Wayland; `systemctl --failed` empty.
- Display/rotation/backlight and the ABL boot flow verified.
- The tablet is currently running this installation; HarmonyOS boot images
  remain in `/usr/local/share/matepad/harmonyos-images` for the return path.

## M3 — hardware bring-up on GNOME (mostly complete)

Verified on the device: GPU (freedreno FD650), touch, M-Pencil (with
calibration), Bluetooth keyboard (patched BlueZ), Wi-Fi, audio playback and
microphone, sensors/auto-rotation, suspend/resume, battery and direct
charging, USB serial console.

Still open: camera userspace, USB-C/DP dock, RTC persistence, M-Pencil
magnetic charging/vibrator, WirePlumber 0.5 speaker routing, and a tuned
suspend policy. See `docs/KNOWN-ISSUES.md`.

## M4 — release engineering (pending)

- Pin the apt archive snapshot; produce a real release manifest/checksums.
- Optional Armbian rootfs cache integration and CI.
- Signed image and reproducible `sha256` publication.
