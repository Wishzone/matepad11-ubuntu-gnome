# Known issues and open work

Updated after the first real-device install (2026-11-11). See
`docs/DEVICE-STATUS.md` for the evidence behind each item.

## Open

1. **RTC fixed (2026-11-12).** The boot DTB now contains `sdam@b100` /
   `rtc_offset@7c` and `rtc@6000` has `nvmem-cells = <&rtc_offset>`. `rtc0`
   reads real time and `hwclock -w` persists it; NTP no longer jumps the clock
   from 1970.
2. **Camera works, including the front sensor (2026-11-12).** libcamera and
   PipeWire expose both sensors; standard apps (`gnome-snapshot`, `guvcview`,
   Chrome) can use them. The GC8054 front sensor was mis-declared as
   RGGB in the kernel driver; its real CFA is GRBG, so `GC08A3_MBUS_CODE` is
   now `MEDIA_BUS_FMT_SGRBG10_1X10` (module `gc08a3-grbg.ko`). No CCM or
   shader workaround is used. The temporary preview launchers were removed;
   a real camera app must counter-rotate the preview by the inverse of the
   display orientation. The sensors' DT rotations differ by 180° (front
   `rotation=270`, rear `rotation=90`), so the front needs that extra
   half-turn.
3. **USB-C host/DP/HDMI is not tested.** Direct charging works
   (`Charging`, -913 mA, 2 A input limit). A USB-C dock/hub puts the tablet in
   `power_role=source` and then it does not charge; test a powered dock and a
   DP monitor separately.
4. **M-Pencil magnetic charging and vibrator are not staged.** The pen pairs,
   writes and has pressure; the STWLC33 charging service and vibrator helpers
   from the recovery tree are not installed.
5. **WirePlumber 0.5 routing/EQ.** Playback and microphone capture work
   through the default UCM/pipewire route. The Kubuntu 0.4 Lua speaker
   routing/orientation EQ is staged only as reference under
   `/usr/share/matepad/wireplumber-0.4`; the SPA-JSON port remains.
   **Charging display** uses a UPower LD_PRELOAD shim because UPower 1.91
   treats negative `current_now` as discharging; the long-term fix is to
   expose positive charging current from `matepad-fg.c` and rebuild the
   kernel/boot image.
   **Cheese** is not in Ubuntu 26.04; `gnome-snapshot` and `guvcview` are
   installed as camera test apps. Chrome is installed from Google's arm64
   `.deb` and is not redistributed in the image.
6. **The tuned KDE suspend script is not ported.** GNOME/logind suspend and
   resume are verified, but the previous `matepad-suspend.sh` (dark-wake
   filtering, USB re-authorization, WoWLAN) was KDE/KWin/kscreen-doctor
   specific. Use the default for now; port only if real-world sleep drain is
   unacceptable.
7. **Display scale is a first-login heuristic.** Mutter chose 1.25 with
   `text-scaling-factor=1.5`. It is usable; the user can select 2.0 in
   Settings → Displays. A generated `monitors.xml` with scale 2.0 is still a
   possible improvement.
8. **The current microSD install is older than the v2 image.** The running
   system received the keyboard BlueZ, pen calibration and serial-getty fixes
   live. The source tree and the v2 image include them; reinstalling is only
   needed to reproduce from scratch, not to keep using the tablet.
9. **Build is rootless via fakeroot.** Package ownership in the ext4 image is
   verified, but a few maintainer-script side effects that need real root
   (ACLs, some `/run` state) are skipped. A real-root build remains the
   reference for a release.
10. **No signed release / CI / apt snapshot pinning.** The image records
    `*.packages` but a later rebuild may pick newer Resolute updates. Pin a
    snapshot for reproducible releases.
11. **No Huawei firmware is in the image.** The installer copies
    `a650_zap.*`, `adsp.*`, `slpi.*`, `venus.*` and vendor files from the
    tablet. A standalone image without the installer lacks Wi-Fi/DSP/GPU-zap
    firmware.
12. **`sudo-rs` and classic sudo are both installed.** The alternative is set
    to `/usr/bin/sudo.ws`; remove `sudo-rs` for a leaner image if desired.
13. **Touch tracking-ID warnings fixed in `7.0.14-dby-w09 #4`.**
    `huawei-thp-lite` now reports Type-B slots keyed by Huawei's fixed finger
    array and lets the input core manage tracking-ID lifetimes; the Huawei ioctl
    configuration is unchanged. The kernel was installed and rebooted; the
    new input device exposes ten slots and no duplicate-ID warnings have
    appeared since boot. Type-A/Type-B virtual tests pass for taps, long press,
    wheel scrolling and portrait/landscape rotation transitions. A real
    finger/pen interaction check remains useful.
14. **SLPI resume crash mitigation verified once.** A 20-second RTC-wake test
    on `#4` used the new hook to stop `hexagonrpcd-sdsp` and cleanly stop
    `remoteproc0` before suspend; wake restarted SLPI/FastRPC and rediscovered
    the accelerometer in about four seconds. No `sensor_process` fatal or
    failed units appeared. Repeat physical sleep/wake cycles are still useful.
15. **Brightness persistence installed.** The backlight follower now adopts
    the early-boot value from `systemd-backlight`, persists the last nonzero
    user choice, and restores it on DSI DPMS-on and system resume. The driver
    balances regulator references on blank/unblank. Nine unit tests pass and
    an RTC suspend/wake preserved brightness 174/255. The updated module builds
    for `7.0.14-dby-w09` and is loaded after a controlled reboot; post-boot
    current, MatePad persistent, and systemd values all matched at 161/255. The
    guarded installer created dated backups, verified the microSD root, and did
    not write boot partitions.
16. **Terminal monospace spacing corrected.** The configured `Ubuntu Sans Mono`
    font was absent, causing Fontconfig to fall back to a CJK proportional font.
    Installing `fonts-ubuntu` restores the intended terminal glyph metrics; the
    package is also included in the rootfs build manifest.
17. **Native touchscreen pinch is filtered for two-finger scrolling.** The
    gesture daemon now grabs the direct-touch evdev node, emulates one-finger
    input as a pointer, and converts two-finger motion/tap to wheel/right-click.
    Type-A/Type-B virtual gesture tests pass; physical verification of single-
    finger taps/drags and two-finger scrolling after this change is pending.

## Cosmetic noise (left as-is)

- `DSI PLL(0) lock failed` + `clk_core_*` WARN at boot: the unused second DSI
  shares the display clock tree. Disabling `dsi@ae96000`/`phy@ae96400` makes
  MDSS/DSI0 fail to probe (no `card1-DSI-1`, no `/sys/touchscreen`, Dummy
  audio), so they stay enabled; the warnings are harmless.
- SLPI sensor PD may fail to advertise SEE service 400 on a warm boot;
  `AccelerometerOrientation` becomes `undefined` and GNOME stops rotating.
  `matepad-sensor-recover.service` restarts the SLPI/hexagonrpcd/sensord
  automatically after boot.

- q6asm logs `Memory_map_regions failed` once per session start before the
  UCM backend route is applied. Audio recovers and plays normally.
- `a650_sqe.fw` first load returns -2; the zstd fallback then loads it.
- `qcom-pcie ... dummy regulator`, `ufshcd vdd-hba`, `adreno vdd/vddcx`:
  optional supplies are missing from the DT; the devices work.
- `Kernel image misaligned at boot`, `psci PC mode -3`, UEFI/DMI/cmdline:
  Android bootloader noise.
- libcamera warns about missing `gc08a3`/`ov13b10` tuning and sensor helper
  files; the front colour is fixed at the driver format level (GRBG).

## Resolved on the device

- Real ABL boot, ext4 mount, GDM and GNOME Wayland session.
- Panel, rotation (landscape), SYH62758 backlight and brightness.
- freedreno FD650 GPU (EGL/OpenGL 4.6, Vulkan Adreno).
- Touch (`input_mt_wrapper`, real events) and M-Pencil (`huawei,ts_pen`):
  both follow the display orientation. The `matepad-keyboard-dock` hall
  sensor is disabled in the DT and huawei-thp-lite registers a permanent
  `matepad-tabletmode` switch, so the magnetic keyboard no longer disables
  auto-rotation. The finger is transformed natively by Mutter; the pen is
  rotated in huawei-thp-lite via `/sys/touchscreen/rotation`
  (matepad-volkeys writes `(display + 3) % 4`). The old static
  `0 1 0 -1 0 1` matrix was removed.
- Bluetooth keyboard: patched BlueZ 5.85 creates `HUAWEI MatePad Keyboard`
  input; user confirmed typing.
- Wi-Fi (QCA6390), SSH, DHCP/DNS.
- Audio playback and microphone capture; TFA9874 amp service.
- Sensors and auto-rotation, including with the magnetic keyboard attached
  (kernel `matepad-tabletmode` switch).
- Boot to `graphical.target` in about 9 seconds: RTC fixed, and the sensor
  services no longer hold the multi-user transaction.
- Suspend/resume with SSH/Wi-Fi recovery; no failed unit.
- Battery/UPower and direct charging (2 A input, negative battery current).
- USB serial console (`serial-getty@ttyGS0`, verified login).

## Notes that are not bugs

- Auto-rotation is disabled while the magnetic keyboard/folio is attached:
  the `matepad-keyboard-dock` switch puts GNOME in laptop mode. Detach it for
  tablet auto-rotation.
- A non-PD charger/dock may stay at `power_role=source`; use a direct charger
  or a powered dock that negotiates sink.
- The previous `#3` kernel logged “double tracking ID” from its Type-A touch
  reporter. The active `#4` kernel now uses Type-B slots.
