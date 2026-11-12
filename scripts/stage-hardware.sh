#!/bin/bash
# Stage the hardware support from kubuntu-dby-w09 into the arm64 rootfs.
#
# Only the desktop-agnostic, system-level pieces are staged here. The KDE
# components (Plasma applet, KWin/KRunner, SDDM, KScreen auto-rotation,
# Maliit/Plasma OSK, KDE tray helpers, qtwayland patch) are deliberately not
# installed. GNOME equivalents live in configs/rootfs.
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
S=${S:-$PROJ/upstream/kubuntu-dby-w09}
R=${R:-$PROJ/build/rootfs}
C=$PROJ/configs/rootfs

[ -d "$S/touch" ] || { echo "missing upstream kubuntu-dby-w09 at $S" >&2; exit 1; }
[ -d "$R/etc" ] || { echo "missing rootfs at $R" >&2; exit 1; }

I() { install -D -m "$1" "$2" "$R$3"; }

# ---- touch: Huawei aptouch_daemon through binderfs -------------------------
I 755 "$S/touch/linux70-touch.sh" /usr/local/lib/linux70-touch/linux70-touch.sh
I 644 "$S/touch/linux70-touch.service" /etc/systemd/system/linux70-touch.service
I 644 "$PROJ/overrides/touchscreen/matepad-touch-rightclick.conf" /etc/matepad-touch-rightclick.conf
I 644 "$PROJ/overrides/touchscreen/matepad-touch-rightclick.service" /etc/systemd/system/matepad-touch-rightclick.service

# Touch/pen rotation is handled in the kernel driver
# (upstream/linux-dby-w09/touch/huawei-thp-lite.c): it exports
# /sys/touchscreen/rotation (pen transform) and registers the
# matepad-tabletmode SW_TABLET_MODE switch.  matepad-volkeys writes the
# orientation to both files.

# ---- sensors: SLPI over QRTR / FastRPC ------------------------------------
I 644 "$S/sensors/hexagonrpcd-sdsp.service" /etc/systemd/system/hexagonrpcd-sdsp.service
# Wait for the SLPI remoteproc to publish /dev/fastrpc-sdsp. Without this the
# daemon starts before the DSP exists, retries every 3 s and floods the kernel
# log with QRTR lookup errors on a machine that has no SLPI (e.g. QEMU).
install -d "$R/etc/systemd/system/hexagonrpcd-sdsp.service.d"
cat > "$R/etc/systemd/system/hexagonrpcd-sdsp.service.d/wait-for-device.conf" <<'EOF'
[Unit]
Wants=dev-fastrpc\x2dsdsp.device
After=dev-fastrpc\x2dsdsp.device
EOF
I 644 "$S/sensors/matepad-sensord.service" /etc/systemd/system/matepad-sensord.service
I 644 "$S/sensors/net.hadess.SensorProxy.conf" /etc/dbus-1/system.d/net.hadess.SensorProxy.conf
# Do not order the sensor daemon before the display manager: the SLPI can
# take a long time on some boots, and GDM must not wait for it.
sed -i '/^Before=/d' "$R/etc/systemd/system/matepad-sensord.service"
# Start the sensor chain from the FastRPC device instead of the boot
# transaction.  The udev event is emitted once /dev/fastrpc-sdsp exists.
install -d "$R/etc/udev/rules.d"
cat > "$R/etc/udev/rules.d/99-matepad-fastrpc.rules" <<'EOF'
ACTION=="add", SUBSYSTEM=="misc", KERNEL=="fastrpc-sdsp", TAG+="systemd", ENV{SYSTEMD_WANTS}+="hexagonrpcd-sdsp.service"
EOF
install -d "$R/etc/systemd/system/hexagonrpcd-sdsp.service.d"
cat > "$R/etc/systemd/system/hexagonrpcd-sdsp.service.d/start-sensors.conf" <<'EOF'
[Unit]
Wants=matepad-sensord.service
EOF
install -d "$R/etc/systemd/system/matepad-sensord.service.d"
cat > "$R/etc/systemd/system/matepad-sensord.service.d/start-volkeys.conf" <<'EOF'
[Unit]
Wants=matepad-volkeys.service
EOF
# Recover the SLPI sensor PD when SEE service 400 never appears at boot.
I 755 "$PROJ/overrides/sensors/matepad-sensor-recover" /usr/local/sbin/matepad-sensor-recover
I 644 "$PROJ/overrides/sensors/matepad-sensor-recover.service" /etc/systemd/system/matepad-sensor-recover.service
I 755 "$PROJ/overrides/sensors/matepad-system-sleep" /usr/lib/systemd/system-sleep/matepad-sensors
install -d "$R/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/matepad-sensor-recover.service \
	"$R/etc/systemd/system/multi-user.target.wants/matepad-sensor-recover.service"
# hexagonrpcd is built into /usr/local by build-tools/hexagonrpc.
printf '/usr/local/lib/aarch64-linux-gnu\n' > "$R/etc/ld.so.conf.d/matepad-local.conf"

# ---- sound: TFA9874, UCM2, PipeWire ---------------------------------------
I 644 "$S/sound/matepad-tfa9874.service" /etc/systemd/system/matepad-tfa9874.service
sed -i 's|matepad-tfa9874 watch$|matepad-tfa9874 watch /proc/asound/HuaweiMatePad11/pcm0p/sub0/status|' \
	"$R/etc/systemd/system/matepad-tfa9874.service"
I 644 "$S/sound/volkeys/matepad-volkeys.service" /etc/systemd/system/matepad-volkeys.service
sed -i '/^Before=matepad-plasma-wayland\.service$/d' "$R/etc/systemd/system/matepad-volkeys.service"
install -d "$R/etc/systemd/system/matepad-volkeys.service.d"
printf '[Service]\nEnvironment=MATEPAD_VOLKEYS_INPUTS=gpio-keys,pm8941_resin,pm8941_pwrkey,matepad-cover\n' \
	> "$R/etc/systemd/system/matepad-volkeys.service.d/linux70.conf"
I 644 "$S/sound/ucm2/Huawei-MatePad-11-DBY-W09.conf" /usr/share/alsa/ucm2/conf.d/sm8250/Huawei-MatePad-11-DBY-W09.conf
I 644 "$S/sound/ucm2/Huawei-MatePad-11-DBY-W09-HiFi.conf" /usr/share/alsa/ucm2/conf.d/sm8250/Huawei-MatePad-11-DBY-W09-HiFi.conf

# PipeWire 1.6 filter-chain files are version-independent. The WirePlumber
# 0.4 Lua rules are staged under /usr/share/matepad/wireplumber-0.4 for
# reference only; 26.04 ships WirePlumber 0.5, whose SPA-JSON rules are a
# port still to do (see docs/KNOWN-ISSUES.md).
for f in 26-matepad-realtime.conf; do
	I 644 "$S/sound/pipewire/$f" "/etc/security/limits.d/$f"
done
I 644 "$S/sound/pipewire/user-realtime.conf" /etc/systemd/system/user@.service.d/matepad-realtime.conf
I 644 "$S/sound/pipewire/user-manager-realtime.conf" /etc/systemd/user.conf.d/matepad-realtime.conf
for f in 60-matepad-speaker-eq.conf 62-matepad-clock.conf; do
	I 644 "$S/sound/pipewire/$f" "/etc/pipewire/filter-chain.conf.d/$f"
done
I 644 "$S/sound/pipewire/filter-chain-wait-sink.conf" /etc/systemd/user/filter-chain.service.d/matepad-wait-sink.conf
I 644 "$S/sound/pipewire/directions.wav" /usr/local/share/matepad-sound/directions.wav
install -d "$R/usr/share/matepad/wireplumber-0.4"
for f in 51-matepad-speakers.lua 52-matepad-speakers-raw.lua; do
	install -m 644 "$S/sound/pipewire/$f" "$R/usr/share/matepad/wireplumber-0.4/$f"
done
# The PipeWire files name the card of the Linux 7.0 driver; the upstream
# staging script applies these substitutions.
for f in \
	"$R/etc/pipewire/filter-chain.conf.d/60-matepad-speaker-eq.conf" \
	"$R/etc/systemd/user/filter-chain.service.d/matepad-wait-sink.conf"; do
	[ -f "$f" ] || continue
	sed -i -e 's/alsa_output\.platform-soc_qcom_msm-audio-apr_qcom_q6core-audio_sound\./alsa_output.platform-sound./' \
	       -e 's/konaqrdsndcard/HuaweiMatePad11/g' -e 's/alsa_input\.\*kona\*/alsa_input.*HuaweiMatePad11*/' "$f"
done
# The stock Kubuntu image loaded these through modules-load.d. A failure there
# marks systemd-modules-load.service failed as a whole; use a tolerant oneshot
# instead so a missing/optional module only costs the audio codec stub.
cat > "$R/etc/systemd/system/matepad-modules.service" <<'EOF'
[Unit]
Description=MatePad: QRTR PD mapper and S/PDIF codec stub
DefaultDependencies=no
After=systemd-modules-load.service
Before=hexagonrpcd-sdsp.service matepad-tfa9874.service matepad-panelbacklightd.service

[Service]
Type=oneshot
ExecStart=-/sbin/modprobe qcom_pd_mapper
ExecStart=-/sbin/modprobe snd_soc_spdif_tx
ExecStart=-/sbin/modprobe syh62758_bl
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF
rm -f "$R/etc/modules-load.d/matepad.conf"

# ---- backlight: this tablet is SYH62758 @ i2c-11 0x2e, not RT8555 @ 0x31 ---
KREL=$(cat "$R/usr/lib/matepad/linux-boot/release.txt" 2>/dev/null || echo 7.0.14-dby-w09)
I 644 "$PROJ/overrides/backlight/syh62758_bl.ko" "/usr/lib/modules/$KREL/extra/syh62758_bl.ko"
I 755 "$PROJ/overrides/backlight/matepad-panelbacklightd" /usr/local/sbin/matepad-panelbacklightd
I 644 "$PROJ/overrides/backlight/matepad-panelbacklightd.service" /etc/systemd/system/matepad-panelbacklightd.service
I 755 "$PROJ/overrides/backlight/matepad-system-sleep" /usr/lib/systemd/system-sleep/matepad-backlight

# ---- pen ------------------------------------------------------------------
I 644 "$S/pen/pen.py" /usr/local/lib/matepad-pen/pen.py
I 644 "$S/pen/matepad-pen-bluez.py" /usr/local/lib/matepad-pen/matepad-pen-bluez.py
I 644 "$S/pen/matepad-pen-pair.py" /usr/local/lib/matepad-pen/matepad-pen-pair.py
I 644 "$S/pen/61-matepad-pen-hidraw.rules" /etc/udev/rules.d/61-matepad-pen-hidraw.rules
I 644 "$S/pen/matepad-pen-bluez.service" /etc/systemd/system/matepad-pen-bluez.service
I 644 "$S/pen/matepad-pen-pair.service" /etc/systemd/system/matepad-pen-pair.service

# ---- power / flashlight ---------------------------------------------------
# UPower 1.91 forces "discharging" on a negative current_now; the DBY gauge
# uses Huawei's negative-charging sign. Preload a tiny wrapper for upowerd.
install -d "$R/etc/systemd/system/upower.service.d"
cat > "$R/etc/systemd/system/upower.service.d/10-matepad-sign.conf" <<'EOF'
[Service]
Environment=LD_PRELOAD=/usr/local/lib/matepad-upower-sign.so
EOF

I 755 "$S/power/matepad-chargeled.py" /usr/local/sbin/matepad-chargeled-linux70
I 644 "$S/power/matepad-chargeled-linux70.service" /etc/systemd/system/matepad-chargeled-linux70.service
I 755 "$S/flashlight/matepad-flashlight" /usr/local/bin/matepad-flashlight
I 644 "$S/flashlight/61-matepad-flashlight.rules" /etc/udev/rules.d/61-matepad-flashlight.rules
I 644 "$S/flashlight/matepad-flashlight.desktop" /usr/share/applications/matepad-flashlight.desktop
# GNOME quick settings toggle for the torch (GNOME 45+ extension API).
I 644 "$PROJ/overrides/flashlight/matepad-flashlight@dby-w09/metadata.json" \
	/usr/share/gnome-shell/extensions/matepad-flashlight@dby-w09/metadata.json
I 644 "$PROJ/overrides/flashlight/matepad-flashlight@dby-w09/extension.js" \
	/usr/share/gnome-shell/extensions/matepad-flashlight@dby-w09/extension.js

# ---- USB-C / DisplayPort --------------------------------------------------
I 755 "$S/usb/matepad-hdmi-audio.py" /usr/local/bin/matepad-hdmi-audio-linux70
I 755 "$S/usb/matepad-dp-recover.py" /usr/local/sbin/matepad-dp-recover
I 644 "$S/usb/60-matepad-ddc.rules" /etc/udev/rules.d/60-matepad-ddc.rules
cat > "$R/etc/systemd/system/matepad-dp-recover.service" <<'EOF'
[Unit]
Description=MatePad Linux 7.0 missing DisplayPort EDID recovery
After=systemd-udev-trigger.service

[Service]
ExecStart=/usr/local/sbin/matepad-dp-recover
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
install -d "$R/etc/systemd/user"
cat > "$R/etc/systemd/user/matepad-hdmi-audio.service" <<'EOF'
[Unit]
Description=MatePad Linux 7.0 HDMI/DisplayPort audio hotplug
After=pipewire.service wireplumber.service
BindsTo=pipewire.service
ConditionUser=!@system

[Service]
ExecStart=/usr/local/bin/matepad-hdmi-audio-linux70
Restart=on-failure

[Install]
WantedBy=pipewire.service
EOF

# ---- cameras: device access only; the KDE-independent camera app is optional
I 644 "$S/camera/70-matepad-camera.rules" /etc/udev/rules.d/70-matepad-camera.rules

# ---- Restart to HarmonyOS -------------------------------------------------
I 755 "$S/boot-switch/matepad-boot-harmonyos" /usr/local/sbin/matepad-boot-harmonyos
I 644 "$S/boot-switch/boot-linux.sh" /usr/local/share/matepad/boot-linux.sh
I 644 "$S/boot-switch/org.matepad.boot-harmonyos.policy" /usr/share/polkit-1/actions/org.matepad.boot-harmonyos.policy
I 644 "$S/boot-switch/matepad-boot-harmonyos.desktop" /usr/share/applications/matepad-boot-harmonyos.desktop
I 755 "$C/matepad-boot-harmonyos-gui" /usr/local/bin/matepad-boot-harmonyos-gui
install -d "$R/etc/skel/Desktop"
I 755 "$S/boot-switch/matepad-boot-harmonyos.desktop" /etc/skel/Desktop/matepad-boot-harmonyos.desktop

# ---- first boot: derive device data from the tablet's own files -----------
I 755 "$S/image/matepad-device-setup" /usr/local/sbin/matepad-device-setup
I 755 "$S/image/matepad-modem-firmware" /usr/local/sbin/matepad-modem-firmware
I 644 "$S/image/matepad-device-setup.service" /etc/systemd/system/matepad-device-setup.service

# ---- GNOME display-manager / first-login integration ----------------------
I 755 "$C/matepad-gdm-autologin" /usr/local/sbin/matepad-gdm-autologin
I 644 "$C/matepad-gdm-autologin.service" /etc/systemd/system/matepad-gdm-autologin.service
I 755 "$C/matepad-gnome-user-setup" /usr/local/bin/matepad-gnome-user-setup
# GNOME can set disable-user-extensions=true on the greeter/fault path; this
# autostart keeps the flashlight quick setting available on every login.
I 755 "$C/matepad-gnome-extensions" /usr/local/bin/matepad-gnome-extensions
I 644 "$C/matepad-gnome-extensions.desktop" /etc/xdg/autostart/matepad-gnome-extensions.desktop
I 644 "$C/matepad-gnome-setup.service" /etc/systemd/user/matepad-gnome-setup.service
I 755 "$C/collect-logs.sh" /usr/local/bin/matepad-collect-logs
I 755 "$C/device-smoke-test.sh" /usr/local/bin/matepad-smoke-test

# User units: enable filter-chain and the HDMI-audio helper for every user.
# (The system units are enabled by configs/rootfs/enable-services.sh inside
# the chroot: `systemctl --root` invokes systemd-sysv-install, which needs a
# real chroot and therefore host root.)
install -d "$R/etc/systemd/user/pipewire.service.wants" "$R/etc/systemd/user/gnome-session.target.wants"
ln -sf /etc/systemd/user/filter-chain.service "$R/etc/systemd/user/pipewire.service.wants/filter-chain.service"
ln -sf /etc/systemd/user/matepad-hdmi-audio.service "$R/etc/systemd/user/pipewire.service.wants/matepad-hdmi-audio.service"
ln -sf /etc/systemd/user/matepad-gnome-setup.service "$R/etc/systemd/user/gnome-session.target.wants/matepad-gnome-setup.service"

echo "staged hardware support into $R"
