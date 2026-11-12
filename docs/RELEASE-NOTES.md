# Release notes — 2026-11-12 (milestone 3)

## Rootfs image

```text
ubuntu-26.04-gnome-dby-w09-20261112.img.xz
SHA-256  ba970b27fd1583f5d0fc44d135aaedba85951a0a0509a419c1b61495b3ea959b
Size     1,252,021,360 bytes compressed
Unpacked 6,302,232,576 bytes
```

The image is a bare ext4 filesystem labelled `LINUX70ROOT`, not a whole-card
image. It contains no Huawei firmware or boot partitions. Install it with the
MatePad installer and use the matching 2026-11-12 boot bundle.

## Included fixes

- `fonts-ubuntu` provides the configured Ubuntu Sans Mono terminal font.
- The SYH62758 backlight driver balances its regulator references; the
  backlight daemon persists the selected level across DPMS, suspend and reboot.
- A system-sleep hook pauses sensor sampling, cleanly stops SLPI before s2idle,
  and relies on FastRPC udev activation after resume. An RTC wake test completed
  without an SLPI `sensor_process` fatal error.
- The touchscreen gesture filter uses pointer emulation for single-finger
  input and synthesizes two-finger scrolling/context clicks. Type-A/Type-B
  synthetic gesture tests pass; physical verification of the filtered path is
  pending.

## Verification

- `python3 -m unittest discover -s tests -v` — 9 tests passed.
- `scripts/verify-image.sh` — PASS, including font, gesture service, and resume
  hook checks.
- `xz -t` and the image `.sha256` sidecar — PASS.
- Device suspend/resume, sensor reconnection and backlight persistence were
  exercised; see `DEVICE-STATUS.md` and `RESUME-FIXES.md`.

Rootfs images and boot bundles are release assets, not git objects. The
repository contains the source, configuration and patches needed to reproduce
the userspace image when the pinned upstream sources and a matching kernel
bundle are available.
