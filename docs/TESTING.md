# Device test plan

Nothing below is marked verified for the GNOME image yet. Run the tests in
order and keep the logs; only then update `docs/COMPATIBILITY.md`.

## Preconditions and safety

- Bootloader unlocked; HarmonyOS rooted; microSD card with the installer.
- Stock `boot`, `ramdisk`, `dtbo` images backed up (the existing backup is
  `edl/backup/20261109-133742/`).
- A way back: installer **Boot Linux** writes the three partitions; fastboot
  can restore the stock images. Huawei ABL rejects `fastboot boot`.
- Do not format or write internal partitions. The image is rootfs-only.
- For the first test, use the microSD route; keep HarmonyOS intact.

## 1. Boot and rootfs

Expected serial console (Linux USB gadget exposes `/dev/ttyACM0` at 115200):

```bash
screen /dev/ttyACM0 115200
```

Commands:

```bash
cat /etc/os-release
uname -a
findmnt /
systemctl --failed
systemctl get-default
systemctl status gdm3 --no-pager
journalctl -b -p err --no-pager
```

Expected:

- `VERSION_ID="26.04"`, `PRETTY_NAME="Ubuntu 26.04.1 LTS"`;
- `/` is `/dev/mmcblk0p1` (or the installer's card partition), ext4,
  `LABEL=LINUX70ROOT`;
- `systemctl --failed` is empty or only documented non-critical units;
- default target `graphical.target`;
- `gdm3.service` active once the graphical target is reached.

If it drops to fastboot: the boot bundle/DTBO is wrong. Restore stock images;
do not guess partitions.

## 2. GDM and GNOME Wayland

```bash
loginctl show-seat seat0 -p ActiveSession
loginctl show-session "$(loginctl show-seat seat0 -p ActiveSession --value)" \
    -p Type -p Desktop -p Active
journalctl -b -u gdm3 --no-pager
journalctl -b -u gnome-shell --no-pager
```

Expected: session type `wayland`, desktop `ubuntu`, active `yes`; no GDM
segfault/DRM failure. If GDM is black but serial works, capture
`dmesg | grep -i -E 'msm|dpu|dsi|panel|backlight'` and `journalctl -b -u gdm3`.

## 3. Display, rotation and backlight

```bash
cat /sys/class/drm/card*-DSI-1/status
cat /sys/class/drm/card*-DSI-1/modes | head
cat /sys/class/backlight/panel0-backlight/{max_brightness,brightness}
ls -l /sys/class/backlight/
```

Expected: `connected`, a 1600×2560 native mode (Mutter rotates it to
2560×1600), `panel0-backlight` present, brightness nonzero.

Set brightness:

```bash
echo 50 | sudo tee /sys/class/backlight/panel0-backlight/brightness
```

If the image is upside down, change the DTB rotation from 90 to 270, rebuild
the boot bundle, and reinstall. Touch orientation must be checked together
with the panel.

## 4. GPU / Adreno 650

```bash
sudo apt install -y mesa-utils vulkan-tools  # already in the image
glxinfo -B 2>/dev/null | head -30
eglinfo -B 2>/dev/null | head -30
vulkaninfo --summary 2>/dev/null | head -40
dmesg | grep -i -E 'msm|adreno|gpu|zap|a650'
```

Expected: renderer `FD650`/`freedreno`, Vulkan device `Adreno (TM) 650`,
no `a650_sqe.fw` fatal error (the `a650_zap.*` shader is copied from the
tablet by the installer).

## 5. Touchscreen and pen

```bash
sudo libinput list-devices
sudo evtest            # choose the pen/stylus device
cat /sys/touchscreen/touch_chip_info
journalctl -b -u linux70-touch --no-pager | tail -50
journalctl -b -u matepad-touch-rightclick --no-pager | tail -50
sudo tests/touchscreen/test-gestures.sh
```

Expected:

- `matepad-touch-rightclick` is active and exposes the virtual pointer;
- one-finger tap/drag works; a held one-finger contact opens context menus on release;
- two-finger parallel motion scrolls and two-finger tap opens context menus;
- native pinch/zoom is suppressed while the gesture filter is active;
- pen produces `ABS_PRESSURE`/`BTN_TOOL_PEN`;
- `linux70-touch` stays active (no AFE SOS/restart loop).

The filter grabs `input_mt_wrapper` and translates single-finger input to a
virtual pointer. Stopping `matepad-touch-rightclick.service` releases the grab
and restores the kernel touchscreen event path.

## 6. Wi-Fi

```bash
nmcli device status
nmcli device wifi list
nmcli device wifi connect "SSID" password "PASSWORD"
ip addr show wlp1s0
ping -c 3 1.1.1.1
journalctl -b -u NetworkManager --no-pager | tail -50
dmesg | grep -i ath11k
```

Expected: `wlp1s0` connected; MAC equals the tablet's stock MAC (installer
copied `/etc/matepad/wlan-mac`); DHCP and DNS work. If firmware is missing,
verify `/usr/lib/firmware/ath11k/WCN6855/hw2.0/` and the installer's
`firmware.txt` copy step.

## 7. Bluetooth

```bash
bluetoothctl show
bluetoothctl scan on
# pair a device, then:
bluetoothctl devices
dmesg | grep -i -E 'btqca|hci|bluetooth'
```

Expected: adapter powered, scan sees devices, pairing works. The Huawei
keyboard HOG fix is **not applied** in this image; if it connects but does not
create an input device, that is the known BlueZ patch gap (see
`docs/KNOWN-ISSUES.md`).

## 8. Audio

```bash
aplay -l
wpctl status
speaker-test -c 2 -t sine -l 1
arecord -l
sudo alsaucm -c HuaweiMatePad11 list 2>/dev/null | head
journalctl -b -u matepad-tfa9874 --no-pager | tail -50
journalctl --user -u pipewire -u wireplumber --no-pager | tail -80
```

Expected: `HuaweiMatePad11` card, speakers audible, microphones capture. If
the card is missing, check `dmesg | grep -i -E 'sm8250|q6|wsa|wcd'` and that
`snd_soc_spdif_tx` loaded (`lsmod | grep spdif`).

## 9. Battery, charging, thermal, suspend

```bash
upower -i /org/freedesktop/UPower/devices/battery_battery
cat /sys/class/power_supply/battery/{capacity,voltage_now,status}
cat /sys/class/power_supply/matepad-charger/online
cat /sys/class/thermal/thermal_zone*/temp
systemctl suspend
# wake with power key; then:
journalctl -b -u systemd-suspend --no-pager | tail -50
cat /sys/kernel/wakeup_reasons/last_resume_reason 2>/dev/null
```

Expected: capacity/voltage plausible, charger online when plugged, suspend
enters and resumes. The KDE-specific upstream suspend loop is not installed;
if suspend behaves badly, capture the logs before changing anything.

## 10. Sensors / auto-rotation

```bash
busctl introspect net.hadess.SensorProxy /net/hadess/SensorProxy
monitor-sensor 2>/dev/null || true
systemctl status matepad-sensord hexagonrpcd-sdsp --no-pager
```

Expected: accelerometer orientation changes when the tablet is rotated; GNOME
Display Settings shows automatic rotation. Rotate with the tablet and verify
the pointer/touch mapping.

## 11. USB-C, DP, flashlight, RTC, camera

```bash
lsusb
cat /sys/class/typec/port*/data_role
cat /sys/class/drm/card*-DP-*/status
echo 1 | sudo tee /sys/class/leds/white:flash/brightness
hwclock -r
```

Expected: dock/host devices enumerate; DP monitor gets an EDID; flashlight
works; RTC reads a sane time. Camera is a separate milestone: the kernel
drivers and access rules are present, but no libcamera/camera app is included.

## 12. Collect evidence

Run on the tablet:

```bash
sudo /usr/local/bin/matepad-collect-logs   # installed by scripts/collect-logs.sh? see below
```

Or from the host with the serial console:

```bash
./scripts/collect-logs.sh --serial /dev/ttyACM0 --out logs/
```

Attach the resulting tarball to the milestone notes. Do not paste Wi-Fi
passwords, SSH keys or personal data.

## Pass/fail gates

| Gate | Pass condition |
| --- | --- |
| G1 boot | login prompt + `systemctl --failed` clean |
| G2 GNOME | GDM Wayland login, GNOME Shell session active |
| G3 display | panel on, correct orientation, brightness control |
| G4 GPU | freedreno renderer + Vulkan device present |
| G5 input | touch + pen events with correct coordinates |
| G6 network | Wi-Fi associated and DNS works |
| G7 audio | speakers and microphone |
| G8 power | battery/charger visible, suspend/resume |
| G9 extras | sensors, USB-C/DP, flashlight, RTC |

Do not mark a gate passed from package presence alone.
