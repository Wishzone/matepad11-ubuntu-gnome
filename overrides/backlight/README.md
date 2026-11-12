# DBY-W09 SYH62758 backlight (kernel driver)

## Actual chip

The tablet's `hw_backlight=hw_syh62758` is a **SYH62758 at I2C bus 11,
address 0x2e**, not the RT8555 at 0x31.  The DTB's old `backlight@31` node is
`status = "disabled"`; the userspace `matepad-backlight` script probes
0x2e/0x2c/0x31 and detected `0x2e syh62758`.

## Kernel driver

`syh62758_bl.ko` (source `syh62758_bl.c`):

- 8-bit register / 8-bit value regmap, max register 0xae.
- Stock `hw_syh62758` 18-entry init sequence.
- 12-bit level in `0x10` (LSB) / `0x11` (low nibble).
- `max_brightness = 255`, CIE 1931 lightness curve, default 115.
- Backlight device: `/sys/class/backlight/panel0-backlight`.
- Uses the existing always-on `bl-en-regulator` as `vcc-supply`; it does not
  request GPIO10, so there is no conflict with the fixed regulator.

DTB additions (current DTB SHA
`86f2eb32342513a4f7c1fd2f460f5bc96e4b47e9a35f8c9ab71fd50c875c943a`):

```dts
bl-en-regulator {
    ...
    phandle = <0x7f4>;
};

&i2c11 {
    backlight@2e {
        compatible = "syh,syh62758";
        reg = <0x2e>;
        vcc-supply = <0x7f4>;
        status = "okay";
    };
};
```

The previous DTB (pen-hall, no backlight node) is backed up on the tablet as
`/usr/lib/matepad/linux-boot/sm8250-huawei-dby-w09.dtb.before-backlight`
(SHA `b0b56b00...`).

## DPMS follower

`matepad-panelbacklightd` no longer writes I2C. It adopts the value restored
by `systemd-backlight`, persists the last nonzero user choice in
`/var/lib/matepad/panel-brightness`, and watches
`/sys/class/drm/card*-DSI-1/dpms`:

- panel off -> save brightness, write 0
- panel on  -> restore saved brightness (default 115 only on a fresh install)
- suspend pre/post -> save and restore the nonzero value around s2idle

The resume hook restores brightness only while the DSI output is on, so it
does not light a screen that the user intentionally left blank. The persistent
per-device value also prevents the driver's probe default (115) from replacing
the user's setting after boot.

## Verified

```
/sys/class/backlight/panel0-backlight -> .../i2c-11/11-002e/backlight/panel0-backlight
max_brightness=255
brightness=115
```

Writing 50/115 via sysfs changes the screen; KDE's brightness slider and the
keyboard brightness keys work.  `matepad-panelbacklightd` is active.

## Old userspace tool

`/usr/local/sbin/matepad-backlight` is still installed for recovery, but it
writes the chip directly over I2C and must not be used while the kernel
driver is active.  Use the KDE slider, the brightness keys, or:

```sh
echo 50 | sudo tee /sys/class/backlight/panel0-backlight/brightness
```

## Files

- `syh62758_bl.c`, `Makefile` — driver source/build
- `syh62758_bl.ko` — built module
- `add-backlight.py` — DTB patch helper
- `install-backlight.sh` — tablet-side installer
- `matepad-panelbacklightd`, `matepad-panelbacklightd.service` — sysfs DPMS follower

## Rollback

Restore
`/usr/lib/matepad/linux-boot/sm8250-huawei-dby-w09.dtb.before-backlight`
as `sm8250-huawei-dby-w09.dtb`, update `SHA256SUMS`, run
`/usr/sbin/matepad-kernel-install`, and reboot.  The old userspace
`matepad-backlight` tool and the previous DPMS follower can then be used
again if needed.
