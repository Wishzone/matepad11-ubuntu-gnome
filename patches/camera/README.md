# Front camera: GalaxyCore GC8054 (DBY-W09)

The front sensor is a GC8054 (GalaxyCore, HOS module
`c441fzb_m180_module`), handled by the mainline `gc08a3` driver with the
GC8054 mode tables from Huawei's Kobe2 GPL source.

## Hardware

- CCI1 bus 0, 7-bit address `0x31`.
- Chip ID `0x8054` at register `0x03f0`.
- 3264x2448, 2-lane D-PHY, MCLK2 24 MHz, link frequency 662.4 MHz.
- Reset GPIO 78; AVDD 2.8 V (`cam_avdd_2p8`), DVDD 1.2 V
  (`cam_front_dvdd`), DOVDD 1.8 V (PM8150L L5).
- Stream on: `0x0102 = 0x09`; stream off: `0x0102 = 0x00`.

## Colour fix (2026-11-12)

The first working image was magenta: mean RGB `[97, 79, 97]`, i.e. R = B > G.
The driver declared the sensor as RGGB, but the GC8054 CFA is **GRBG**.
With a wrong phase the soft ISP samples the two green sites as R and B, and
the real R/B sites as G, which produces exactly that magenta cast.

Verified on hardware with the sensor's own test pattern:

| Driver declaration | "Solid Red" test pattern |
| --- | --- |
| `SRGGB10` | rendered pure green (R=0, G=150, B=0) |
| `SGRBG10` | normal white ceiling, normal skin tones |

The fix is one line in `gc08a3-gc8054.c`:

```c
#define GC08A3_MBUS_CODE MEDIA_BUS_FMT_SGRBG10_1X10
```

No CCM, colour matrix or shader is used.

## Device tree

The stock DBY DTB has no front sensor node. The boot DTB needs:

- `camera@31` under `cci@ac50000/i2c-bus@0`, compatible
  `galaxycore,gc08a3`, `reset-gpios = <&tlmm 78 GPIO_ACTIVE_LOW>`,
  `avdd/dvdd/dovdd` supplies, `rotation = <270>`, `orientation = <0>`,
  endpoint with `data-lanes = <1 2>` and
  `link-frequencies = <0 662400000 0 175200000>`.
- CAMSS `port@2` endpoint with `clock-lanes = <7>`,
  `data-lanes = <0 1>`, linked to the sensor endpoint.
- `cam-front-rails-state` pinctrl (GPIO 26 + GPIO 153 as GPIO) and
  `regulator-always-on` + that pinctrl on `cam_avdd_2p8` and
  `cam_front_dvdd`.

The tested boot image is listed in `docs/HARDWARE-NOTES.md`. The installer
writes each tablet's own Bluetooth address into the DTB; never commit a
device MAC.

## Build

The driver is a replacement for the in-tree `gc08a3.c`:

```bash
KSRC=${KSRC:?set KSRC to the Linux 7.0.14-dby-w09 source}
OUT=${OUT:-$KSRC/../out}

cp patches/camera/gc08a3-gc8054.c "$KSRC/drivers/media/i2c/gc08a3.c"

export CROSS_COMPILE=aarch64-linux-gnu-
make -C "$KSRC" O="$OUT" ARCH=arm64 \
     drivers/media/i2c/gc08a3.ko
```

The kernel config must have `CONFIG_VIDEO_GC08A3=m`.

## Install

```bash
install -m 644 gc08a3.ko \
  /lib/modules/7.0.14-dby-w09/updates/matepad/gc08a3.ko
depmod -a
reboot
```

The module is tied to `7.0.14-dby-w09`; rebuild it after a kernel change.

## Verify

```bash
media-ctl -p -d /dev/media0 | grep gc08a3
cam -l                       # or: gst-device-monitor-1.0 Video/Source
```

`/sys/class/video4linux/` and the PipeWire camera node both expose the
sensor. The camera launcher selects the front camera by its media path
(`cci@ac50000/i2c-bus@0/camera@31`), not by a fixed index.

## Files

- `gc08a3-gc8054.c` — patched driver with GC8054 tables and GRBG.
- `gc08a3-gc8054.patch` — the original chip-ID acceptance patch, kept for
  reference.
