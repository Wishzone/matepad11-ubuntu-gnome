# Hardware notes — DBY-W09

These are the non-obvious hardware facts behind the patches. They were
established on a physical MatePad 11 and are the reason the boot DTB is a
**minimal delta** over the tablet's stock DTB, not a wholesale replacement.

## Display

- The panel is physically portrait (1600×2560) and mounted rotated. The stock
  DTB's `panel@0` needs `rotation = <0x5a>` (90°) so GNOME sees a 2560×1600
  landscape output.
- Replacing the whole DTB with the front-camera DTB dropped this property and
  the backlight/Bluetooth nodes; that caused the touch/rotation/brightness
  regressions seen during bring-up. Always patch the stock DTB.

## Backlight

- The IC is **SYH62758 at i2c-11 0x2e**, not the RT8555 at 0x31 described by
  the stock node. `scripts/patch-dtb.sh` adds `backlight@2e`
  (`syh,syh62758`) and the `bl-en-regulator` phandle.
- `syh62758_bl.ko` exposes `/sys/class/backlight/panel0-backlight`
  (`max_brightness=255`). It must match the kernel vermagic.

## Touch and M-Pencil

- `aptouch_daemon` writes finger data to `/dev/input_mt_wrapper`; the kernel
  `huawei-thp-lite` driver turns it into input events.
- **Finger**: Mutter maps the touchscreen and applies the output transform
  once a tablet-mode switch exists. The old fixed
  `LIBINPUT_CALIBRATION_MATRIX` was removed.
- **Auto-rotation**: GNOME disables it when it sees no `SW_TABLET_MODE`
  switch. The keyboard-dock hall sensor is disabled in the DT (the user wants
  rotation with the keyboard attached), so the kernel driver registers a
  permanent `matepad-tabletmode` input device with `SW_TABLET_MODE=1`.
- **Pen**: Mutter treats the M-Pencil as a tablet tool and does **not** apply
  the output transform to it. The driver therefore rotates the pen
  coordinates itself via `/sys/touchscreen/rotation` (0..3).
  `matepad-volkeys` writes `(display_rotation + 3) % 4`, because the pen's
  native frame is 90° away from the finger/display frame.
- The sensor `rotation` values are `270` (front) and `90` (rear); they differ
  by 180°. A camera preview app must counter-rotate by the inverse of the
  display orientation and add that half-turn for the front camera.

## Cameras

- Rear: OV13B10, CCI0 bus 0 `0x36`, 4-lane.
- Front: GC8054 (GC08A3-compatible), CCI1 bus 0 `0x31`, 2-lane, chip ID
  `0x8054`. **The CFA is GRBG, not RGGB.** Declaring RGGB produced a magenta
  image (R≈B>G); `SGRBG10` fixes it with no CCM/shader.
- Both sensors are exposed through libcamera/PipeWire. The front sensor needs
  the `camera@31` node and the CAMSS `port@2` endpoint (see
  `patches/dtb/README.md`).
- Use the media path (`cci@ac50000/i2c-bus@0/camera@31`) to select the front
  camera; probe order is not stable.


## Sensor boot recovery

On some boots the SLPI remoteproc is running but the SEE sensor PD (QRTR
service 400) never appears. `matepad-sensord` then waits forever,
`AccelerometerOrientation` stays `undefined`, and GNOME cannot rotate the
screen. `matepad-sensor-recover.service` waits up to 60 s after boot and, if
the accelerometer never starts, restarts the SLPI remoteproc plus
`hexagonrpcd-sdsp` and `matepad-sensord`. It runs after `multi-user.target`,
so it never delays boot.

An RTC-wake test on kernel `#4` also captured a fatal SLPI sensor-process error
immediately after s2idle. The sensor chain recovered in about seven seconds.
`matepad-sensord` has a suspend handshake and refreshes its SEE client after
wake. Since pause-and-refresh alone still coincided with the fatal error, the
revised system-sleep hook also stops `hexagonrpcd-sdsp` and cleanly stops SLPI
before s2idle, then starts SLPI and FastRPC after wake. It passed a 20-second
RTC-wake test on the tablet: the accelerometer was rediscovered in about four
seconds and no SLPI fatal error followed. Repeat sleep/wake cycles remain
useful for longer-term confidence.


## GNOME user extensions

GNOME can set `org.gnome.shell disable-user-extensions=true` on the greeter
or fault path. That hides every quick-settings extension, including the
flashlight toggle. `matepad-gnome-extensions` runs from `/etc/xdg/autostart`
on every login, sets the key back to `false` and enables
`matepad-flashlight@dby-w09`. `gnome-extensions enable` loads it dynamically,
so no session restart is required.

## RTC

- `rtc-pm8xxx` is present in the stock DTB but reads 1970 because the PM8150
  SDAM offset is not described. Add `sdam@b100`, the `rtc_offset@7c` nvmem
  cell and `nvmem-cells` on `rtc@6000`. `hwclock -w` then persists the time.

## Audio

- The SM8250 backend supports 4 channels/S16. The ACP probe opened 8
  channels/S24 and failed with `EINVAL`, leaving only "Dummy Output".
  `q6asm-dai` playback is forced to S16 + 4 channels (see
  `patches/sound/`).

## Bluetooth

- The QCA6390 controller needs the tablet's own address. The stock DTB has
  `local-bd-address = [00 00 00 00 00 00]`; the installer (or
  `set_bd_address.py`) writes `/etc/matepad/bt-mac` into the DTB. Never commit
  a device MAC.
- Bluetooth HFP/HSP (headset microphone) needs `CONFIG_BT_RFCOMM`; the
  upstream build script only enabled `BT`/`BT_HCIUART`/`BT_QCA`.
  `patches/0002-enable-bt-rfcomm.patch` adds `BT_RFCOMM=m` and
  `BT_RFCOMM_TTY=y`. Without it `bluetoothd` logs `RFCOMM server failed ...
  Protocol not supported (93)` and HFP is unavailable; A2DP can still work.

## Do not disable the second DSI

- `dsi@ae96000` / `phy@ae96400` are unused for the panel (the panel is on
  `dsi@ae94000`), but they share the display clock tree. Setting
  `status = "disabled"` on them makes MDSS/DSI0 fail to probe: the
  `card1-DSI-1` connector and `/sys/touchscreen` disappear and audio falls
  back to Dummy Output.
- The `DSI PLL(0) lock failed` / `clk_core_disable` warnings at boot are
  cosmetic. Leave the second DSI enabled.

## Boot time

- The SLPI sensor stack (`hexagonrpcd-sdsp` → `matepad-sensord` →
  `matepad-volkeys`) waits for `/dev/fastrpc-sdsp`. Starting it from
  `multi-user.target` held the boot transaction for ~90 s. It is now started
  by a udev rule when the FastRPC device appears; GDM no longer waits for it.
- With the RTC fixed and the services decoupled, boot to
  `graphical.target` is about 9 s.
