#!/bin/bash
# Enable the system services inside the arm64 rootfs. Run through
# scripts/rootfs-chroot.sh (fake root in a user namespace).
set -euo pipefail
systemctl --no-reload enable \
	linux70-touch.service \
	matepad-touch-rightclick.service \
	matepad-tfa9874.service matepad-pen-bluez.service \
	matepad-pen-pair.service matepad-dp-recover.service \
	matepad-chargeled-linux70.service matepad-device-setup.service \
	matepad-gdm-autologin.service matepad-modules.service \
	matepad-panelbacklightd.service \
	bluetooth.service NetworkManager.service ssh.service \
	systemd-timesyncd.service
systemctl --no-reload enable gdm3.service
# Development/debug console: the DBY initramfs exposes a USB ACM gadget and
# Linux runs a login prompt on ttyGS0. It is password-protected by the user
# account; no autologin is configured on this console.
systemctl --no-reload enable serial-getty@ttyGS0.service
systemctl set-default graphical.target
echo "enabled:"
systemctl is-enabled gdm3.service linux70-touch.service NetworkManager.service 2>&1 || true
