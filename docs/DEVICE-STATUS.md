# Real-device status — 2026-11-12

Installed on a physical Huawei MatePad 11 (DBY-W09) from the clean-build
image via the existing installer. This file records what was actually tested,
not what the package set implies.

Device / session:

- Ubuntu 26.04 LTS, kernel `7.0.14-dby-w09 #4`
- GNOME Shell 50 / GDM 50 on Wayland
- SSH enabled; USB ACM console enabled and verified
- No user name, password, IP address or Wi-Fi SSID is stored in this repository

## Passed on the device

| Area | Evidence |
| --- | --- |
| Boot / rootfs | `systemd-analyze`: about **9 s** to `graphical.target`; `systemctl --failed` empty |
| Display | `/sys/class/drm/card1-DSI-1/status=connected`; visible desktop; auto-rotate with and without the magnetic keyboard |
| Terminal font | Installed missing `fonts-ubuntu`; `Ubuntu Sans Mono` now resolves to its Ubuntu font file instead of the Noto CJK fallback |
| Backlight | Persistent daemon installed; 174/255 stayed through RTC suspend/wake; after reboot, current/persistent/systemd values matched at 161/255 and updated SYH62758 module was loaded |
| GPU | `eglinfo -B`: `OpenGL core profile renderer: FD650`, Mesa 26.0.8; `vulkaninfo` Adreno |
| Touch | Type-B `input_mt_wrapper` with ten slots in kernel `#4`; filtered single-pointer/two-finger gesture daemon installed; synthetic Type-A/Type-B tests pass; physical touch retest pending |
| M-Pencil | `huawei,ts_pen`; pressure and buttons work; pen follows the display in all four orientations |
| Bluetooth keyboard | patched BlueZ 5.85; `HUAWEI MatePad Keyboard` creates an input device; typing confirmed |
| Wi-Fi | QCA6390 associated; SSH and DHCP/DNS work |
| Bluetooth | QCA6390 adapter up; keyboard and M-Pencil paired |
| Audio | `HuaweiMatePad11` card; hardware sink at 1.0; Chrome playback confirmed |
| Sensors / rotation | `net.hadess.SensorProxy` `HasAccelerometer=true`; `AccelerometerOrientation` changes; GNOME rotates the panel |
| RTC | `/sys/class/rtc/rtc0` reads real time; `hwclock -w` persists across reboot |
| Suspend / resume | Clean SLPI stop/start hook installed; RTC wake on `#4` completed with no `sensor_process` fatal and accelerometer rediscovered in about 4 s; one captured power-key wake completed from kernel resume to systemd operation finish in about 1 s, with no failed units |
| Battery / charging | UPower reports `charging` with the UPower sign shim; direct charger negotiates 2 A |
| Camera | libcamera/PipeWire expose front (GC8054) and rear (OV13B10); front colours correct after the GRBG driver fix |
| USB serial console | `serial-getty@ttyGS0` enabled; login prompt and shell over `/dev/ttyACM0` |

## Fixed during the device sessions

1. **Bluetooth keyboard**: stock BlueZ 5.85 fails the HOG CCC read; patched
   `bluez`/`libbluetooth3` 5.85 debs are built from `overrides/bluez/`.
2. **Touch and pen rotation**: the kernel `huawei-thp-lite` driver registers a
   permanent `SW_TABLET_MODE` switch and exports `/sys/touchscreen/rotation`
   for the pen; `matepad-volkeys` writes the display orientation. No static
   `LIBINPUT_CALIBRATION_MATRIX` and no userspace touch proxy remain.
3. **Auto-rotation with the keyboard**: the `keyboard-dock-sensor` node is
   disabled in the DT; the kernel switch keeps Mutter in tablet mode.
4. **RTC**: the boot DTB has `sdam@b100` / `rtc_offset@7c` and `rtc@6000`
   `nvmem-cells`; `hwclock -w` persists the time.
5. **Front camera colour**: the GC8054 CFA is GRBG, not RGGB; the driver uses
   `MEDIA_BUS_FMT_SGRBG10_1X10`. Verified with the sensor test pattern.
6. **Audio**: `q6asm-dai` playback is S16-only with 4 channels; the ACP probe
   no longer fails with 8 channels.
7. **Boot time**: the SLPI sensor services are started from the
   `/dev/fastrpc-sdsp` udev event instead of the multi-user transaction.
8. **Multitouch event protocol**: `huawei-thp-lite` now exports Type-B slots
   and kernel-managed tracking IDs. The change was built and booted as kernel
   `#4`; Type-A/Type-B virtual tests passed and the prior duplicate-ID warnings
   have not returned since boot.

## Desktop extras installed on the device

- **Google Chrome arm64** from Google's official `.deb`; Chrome is
  proprietary and is deliberately not baked into the redistributable image.
- **IBus Pinyin** (`ibus-libpinyin`). Input sources are `xkb:us` +
  `ibus:libpinyin`; switch with **Super+Space**.
- **Camera apps**: Ubuntu 26.04 no longer ships `cheese`; `gnome-snapshot`
  and `guvcview` are available. The temporary preview launchers used during
  bring-up have been removed.
- **Power key**: GNOME `power-button-action='suspend'` and logind
  `HandlePowerKey=suspend`.
- **Flashlight**: desktop action plus a GNOME quick-settings toggle
  (`matepad-flashlight@dby-w09`).
- **UPower sign shim**: `overrides/upower/matepad-upower-sign.c` is compiled
  during rootfs build and makes `upowerd` see positive charging current.

## Still open

- **USB-C host/DP/HDMI** is not tested with a powered dock and a DP monitor.
- **M-Pencil magnetic charging and vibrator** are not staged.
- **WirePlumber 0.4-era speaker routing/EQ** is not ported to 0.5.
- **Suspend drain**: the KDE-specific tuned suspend script is not ported;
  the default logind behaviour is used.
- **Release/CI**: images and boot bundles are built locally and attached to
  GitHub Releases; there is no signed release or apt snapshot pinning yet.
