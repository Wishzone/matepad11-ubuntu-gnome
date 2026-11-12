# Hardware compatibility matrix — DBY-W09 + Ubuntu 26.04 GNOME

Status vocabulary:

- **Verified**: tested on this physical DBY-W09 and evidence is recorded.
- **Source/upstream verified**: the driver/service is present in the existing
  DBY port and was reported working there, but this *new GNOME image* has not
  been booted on the tablet.
- **Installed, untested**: packages/services are in the image; no device test.
- **Not supported**: absent or known not to work.

Nothing in this table is marked “Verified” for the GNOME image until the device
test in [`TESTING.md`](TESTING.md) has been run. The previous Kubuntu install on
this tablet is recorded separately as historical evidence.

## Boot and system

| Area | Source / implementation | State | Evidence / notes |
| --- | --- | --- | --- |
| ABL boot image | `linux-dby-w09/repack_boot.py`, installer builds from stock `boot` | Source/upstream verified | Header v2; DTB in boot image; `fastboot boot` rejected |
| DTBO `/rootparam` | `linux-dby-w09/dby-w09-rootparam.dtso`, `pack_dtbo.py` | Source/upstream verified | Wrong DTBO → ABL returns to fastboot |
| SD-root initramfs | `linux-dby-w09/sd_root_init.sh` + `ramdisk-payload.img` | Source/upstream verified | Mounts `LABEL=LINUX70ROOT`; reboots to fastboot without card |
| Ubuntu 26.04 arm64 rootfs | this project, `configs/apt/ubuntu.sources` | **Verified on device** | Installed to microSD; boots to GDM/desktop; `systemctl --failed` empty |
| systemd | Ubuntu 26.04 systemd 259.9 | **Verified on device** | No failed units; suspend/resume works |
| GDM + GNOME Wayland | `gdm3` 50.1, `gnome-shell` 50.1, `ubuntu-session` | **Verified on device** | GDM/desktop visible, active Wayland session; SSH/serial console work |
| Installer autologin | `configs/rootfs/matepad-gdm-autologin` + service | **Verified in QEMU** (runs) | Translates `/etc/sddm.conf.d` `User=` to GDM; user not present in QEMU test |
| User creation/locale/keyboard | installer `configure()` | Source verified | Runs `useradd`, `chpasswd`, `locale-gen`, writes `/etc/default/keyboard` |
| Root filesystem growth | `image/build-image.sh` equivalent; installer `resize2fs` | Source/upstream verified | Label `LINUX70ROOT`; `e2fsck` clean |

## Display, GPU and input

| Area | Implementation | State | Evidence / notes |
| --- | --- | --- | --- |
| Panel 190_20d / W2599Z1300 | `linux-dby-w09` panel driver + 60 Hz command table | **Verified on device** | DSI-1 connected, 1600x2560 modes, visible desktop |
| Panel rotation | DTB `rotation = <90>` added by `scripts/patch-dtb.sh` | **Verified on device** | GNOME presents landscape 2560×1600 |
| Backlight SYH62758 @ 0x2e | `overrides/backlight/syh62758_bl.ko` + DTB node | **Verified on device** | `panel0-backlight`, brightness 206/255, module loaded |
| Backlight persistence/DPMS | `matepad-panelbacklightd` + systemd-sleep hook | Installed, RTC/reboot-tested | Preserved 174/255 across suspend/wake; after reboot current/persistent/systemd values matched at 161/255; updated module loaded; nine unit tests pass |
| Adreno 650 / freedreno | Mesa 26.0.8, `msm_dri.so`, `libvulkan_freedreno.so` | **Verified on device** | `eglinfo`: freedreno FD650, OpenGL 4.6; Vulkan Adreno |
| GNOME/Wayland compositor | Mutter 50 via `gnome-shell` | **Verified on device** | Wayland session active; display scaling 1.25, text 1.5 |
| Touchscreen (Novatek W2599Z1300) | `huawei-thp-lite` + Huawei `aptouch_daemon` via binderfs | **Verified on device** | `input_mt_wrapper` event2, real touch events, user confirmed |
| Touchscreen gestures | `matepad-touch-rightclick` filtered evdev/uinput bridge | Installed; synthetic Type-A/Type-B tests pass | Single-finger pointer, two-finger scroll/tap, native multi-touch pinch filtered; physical verification after filter install pending |
| Touch rotation | panel orientation + Mutter mapping | **Verified on device** | Finger touch matches the rotated screen in all four orientations |
| M-Pencil position | touch daemon stylus3 + kernel `sysfs rotation` | **Verified on device** | `huawei,ts_pen`; the driver rotates the pen via `/sys/touchscreen/rotation`; follows all four orientations |
| M-Pencil pressure/buttons | `matepad-pen-bluez` + BlueZ GATT | **Verified on device** | M-Pencil paired/connected; user confirmed writing/pressure |
| On-screen keyboard | GNOME Shell OSK (not Maliit) | Installed, untested | First-login service sets `screen-keyboard-enabled=true` |
| Volume/power keys | `matepad-volkeys`, gpio-keys | Source/upstream verified | Drop-in input list adapted to GNOME (no KDE ordering) |

## Network, audio, power

| Area | Implementation | State | Evidence / notes |
| --- | --- | --- | --- |
| Wi-Fi QCA6390 | `ath11k` + `ath11k_pci` modules, linux-firmware | **Verified on device** | `wlp1s0` associated to the test access point; SSH/DHCP/DNS work |
| Bluetooth QCA6390 | BlueZ 5.85 + `btqca` modules/firmware | **Verified on device** | Adapter up; keyboard and M-Pencil pair/connect |
| Huawei keyboard HOG fix | `overrides/bluez` patched BlueZ 5.85 | **Verified on device** | `HUAWEI MatePad Keyboard` creates event10; user confirmed typing |
| Speakers (4× TFA9874) | `matepad-tfa9874` + UCM2 + PipeWire | **Verified on device** | 440 Hz audible at 100%; amp service switches on/off with playback |
| Microphones WCD938x | kernel SoundWire + UCM2 | **Verified on device** | `pw-record` captured a 520 KB WAV; source present |
| Volume keys orientation | `matepad-volkeys` | Source/upstream verified | Uses `matepad-sensord` orientation |
| Sensors / auto-rotation | `hexagonrpcd` + `matepad-sensord` + Mutter | **Verified on device** | `AccelerometerOrientation=right-up`; rotation works with and without the magnetic keyboard (kernel tablet-mode switch) |
| Battery / charger | `matepad-fg` + UPower | **Verified on device** | 90%/4.18 V; direct charger `Charging`, -913 mA, LED on |
| Charging LED | `matepad-chargeled-linux70` | **Verified on device** | LED observed with direct charger |
| Suspend/resume | logind + GNOME defaults | **Verified on device** | `System returned from sleep`; SSH/Wi-Fi restored; tuned script still not ported |
| RTC | SDAM offset in the boot DTB | **Verified on device** | `rtc0` reads real time; `hwclock -w` persists across reboot |
| Thermal/CPU frequency | kernel cpufreq/OPP tables | Kernel present | GNOME power profiles/PPD not explicitly configured |

## Cameras, USB-C, pen charging, extras

| Area | Implementation | State | Evidence / notes |
| --- | --- | --- | --- |
| Rear OV13B10 + DW9714 | kernel modules + libcamera/PipeWire | **Verified on device** | rear camera streams through PipeWire |
| Front GC8054 | patched `gc08a3` (2-lane, GC8054 tables, GRBG) | **Verified on device** | magenta cast fixed by `SGRBG10`; no CCM/shader |
| Camera access rules | `70-matepad-camera.rules` | Installed | Grants uaccess to media/V4L2/dma-heap |
| USB-C host | kernel dwc3/typec | Kernel present | Needs dock test |
| DP Alt Mode / HDMI audio | `matepad-dp-recover`, `matepad-hdmi-audio` | Installed, untested | User service + udev rules |
| DDC/CI | `60-matepad-ddc.rules` | Installed | For external monitor brightness |
| Flashlight | `matepad-flashlight` + udev + GNOME extension | **Verified on device** | PM8150L flash torch, desktop action and quick settings toggle |
| M-Pencil magnetic charging | STWLC33 userspace from recovery | **Not staged** | Existing Kubuntu had a service; port later |
| Vibrator | upstream `recovery/vibrator` | **Not staged** | Optional |
| GNOME on-screen keyboard | GNOME Shell | Installed | No Maliit/KDE dependency |

## Kernel

| Item | Value |
| --- | --- |
| Version | `7.0.14-dby-w09` |
| Source | `svesnav/linux-dby-w09` + this tablet's 60 Hz/190_20d fixes |
| Modules | `/usr/lib/modules/7.0.14-dby-w09`, depmod run |
| Boot bundle | `/usr/lib/matepad/linux-boot` (Image.gz, DTB, dtbo.img, ramdisk-payload.img, cmdline.txt) |
| Firmware | none from Huawei in the image; installer copies a650_zap/adsp/slpi/venus from the tablet |

The kernel is intentionally **not** upgraded or replaced by an Ubuntu generic
kernel. `linux-image-dby-w09` should be held if it is installed on the device
later; this image ships the bundle and modules directly.
