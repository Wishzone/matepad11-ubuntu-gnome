# Verification record — 2026-11-11

## Artifact

The final image is the clean-build artifact produced by
`scripts/build-rootfs.sh --from-scratch` on 2026-11-11. The build log is
`build/logs/build-rootfs-clean2.log`; its image was checked with
`scripts/verify-image.sh` and booted with `scripts/test-qemu.sh` before being
promoted to `build/out/`.

```text
ubuntu-26.04-gnome-dby-w09-20261111.img.xz
sha256 (see build/out/...sha256 and releases/2026-11-11/SHA256SUMS)
```

`xz -t` and `sha256sum -c` both passed.

## Package versions in the image

```text
ubuntu-desktop-minimal 1.570.4
gnome-shell            50.1-0ubuntu1.5
gdm3                   50.1-0ubuntu0.1
mesa-vulkan-drivers    26.0.8-1ubuntu0.3
pipewire               1.6.2-1ubuntu1.2
wireplumber            0.5.13-1ubuntu1.1
systemd                259.9-0ubuntu0.1
linux-firmware         20260319.git217ca6e4.1ubuntu
```

`build/out/ubuntu-26.04-gnome-dby-w09-20261111.packages` has the full list.

## Image checks

`scripts/verify-image.sh` output: **PASS**. It checked, among others:

- ext4 label `LINUX70ROOT` and legacy-compatible feature set;
- Ubuntu 26.04 `os-release`;
- GNOME Shell and GDM binaries;
- the boot bundle and device-files lists;
- `syh62758_bl.ko` and `hexagonrpcd`;
- `sudo`/`passwd`/`pkexec` 4755, `ssh-agent` 2755 `root:_ssh`,
  D-Bus launcher 4754 `root:messagebus`, `/etc/shadow` 0640 `root:shadow`;
- no `qemu-aarch64-static` or fakeroot state in the image;
- no `plasma-desktop`, no `snapd`;
- a plain `/etc/resolv.conf` (no dangling systemd-resolved symlink);
- `matepad-smoke-test` and `matepad-collect-logs` installed.

## QEMU boot

`scripts/test-qemu.sh` with the DBY kernel in `-M virt`:

```text
Welcome to Ubuntu 26.04.1 LTS!
...
[ OK ] Started NetworkManager.service
[ OK ] Started linux70-touch.service
[ OK ] Started hexagonrpcd-sdsp.service
[ OK ] Started matepad-sensord.service
Ubuntu 26.04.1 LTS matepad ttyAMA0
matepad login:
...
PASS: reached a login prompt with no FAILED unit
```

The clean-build image's exact log is
`build/logs/qemu-20261111-192634.log`; the earlier manual build log is
`build/logs/qemu-20261111-175205.log`. QEMU cannot test the panel/GPU/touch:
the DBY kernel has no `virtio-gpu` and no DBY hardware. GDM/GNOME graphical
start is therefore **not** verified.

## What is not verified

- real-device ABL boot, microSD, installer partition writes;
- GDM/GNOME graphical session, Mutter/Wayland on the Adreno 650;
- panel orientation/backlight, touch/pen, Wi-Fi/BT, audio, sensors, battery,
  suspend, USB-C/DP, RTC, camera.
