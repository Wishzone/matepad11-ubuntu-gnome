# Patches

Everything here is applied to a fetched upstream tree or to a Linux 7.0.14
source tree. The boot bundle was built from the commits pinned in
`upstream.lock`.

| Path | Target | Purpose |
| --- | --- | --- |
| `0001-huawei-thp-lite-tabletmode-pen-rotation.patch` | `upstream/linux-dby-w09` | Kernel touch driver: permanent `SW_TABLET_MODE` switch and `/sys/touchscreen/rotation` pen transform. |
| `0002-enable-bt-rfcomm.patch` | `upstream/linux-dby-w09` | Build `rfcomm.ko` and `BT_RFCOMM_TTY`, so Bluetooth HFP/HSP headsets work. |
| `0003-huawei-thp-type-b-multitouch.patch` | `upstream/linux-dby-w09` | Report Huawei's fixed finger array through Type-B slots with core-assigned tracking IDs. |
| `camera/gc08a3-gc8054.c` | Linux source tree | GC8054 front sensor driver (Kobe2 mode tables, chip ID, 2-lane, **GRBG**). |
| `sound/q6asm-dai-s16-4ch.patch` | Linux source tree | `q6asm-dai` playback S16-only, 4 channels. |
| `dtb/README.md` | Stock DBY DTB | Front camera, RTC SDAM, keyboard-dock, rail pinctrl deltas. |
| `scripts/patch-dtb.sh` | Stock DBY DTB | Panel rotation and SYH62758 backlight node. |

## Apply

```bash
# 1. Fetch the pinned upstream repos and apply the touch/tablet-mode patches.
scripts/fetch-upstream.sh

# 2. Camera + audio patches, against the Linux 7.0.14 source tree.
scripts/apply-kernel-patches.sh /path/to/linux-7.0.14

# 3. Panel/backlight DTB (the extra nodes are in dtb/README.md).
scripts/patch-dtb.sh stock.dtb out.dtb
```

`scripts/fetch-upstream.sh` calls `scripts/apply-patches.sh`, which resets the
driver to the pinned commit and re-applies the touch patch. Re-running it is
safe.

## Tested bundle

The 2026-11-12 boot bundle (kernel + DTB + original ramdisk) is:

```text
boot-kernel-penrot-20261112.img
SHA-256 91556d3f249b7d32466c30795a2de45bd4cc0bf13a6743e926bf0557e1ff9789
kernel  8acac6aa9d43c0416ac3c92a879921fe28a6691991eb1573db3b635adc1e0067  (Image.gz)
```

It is a release asset, not stored in git. `docs/HARDWARE-NOTES.md` explains
the hardware reasons behind each change.

## Phandles

The DTB snippets use the phandle numbers of the tested stock DTB. Resolve them
by node path when starting from a different DTB; `dtc` reports duplicate
phandles if a number is already taken.
