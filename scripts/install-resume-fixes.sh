#!/bin/bash
# Install the DBY-W09 SLPI-suspend and SYH62758 backlight persistence fixes.
# Run as root on a running MatePad 11 Linux installation. This script backs up
# every replaced file; it never writes boot/ramdisk/dtbo partitions.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
	echo "Run as root: $0 <staged-fix-directory>" >&2
	exit 1
fi

STAGE=${1:-$(cd "$(dirname "$0")/../build/resume-fixes" && pwd)}
KREL=$(uname -r)
[[ $KREL == *dby-w09* ]] || { echo "not running the DBY-W09 kernel: $KREL" >&2; exit 1; }
ROOT_SOURCE=$(findmnt -n -o SOURCE /)
[[ $ROOT_SOURCE == /dev/mmcblk* ]] || {
	echo "root is $ROOT_SOURCE, expected the microSD root; refusing to install" >&2
	exit 1
}

for f in matepad-sensord matepad-panelbacklightd matepad-sensor-recover \
	matepad-system-sleep-sensors matepad-system-sleep-backlight syh62758_bl.ko; do
	[[ -s $STAGE/$f ]] || { echo "missing staged file: $STAGE/$f" >&2; exit 1; }
done

MODULE=$(modinfo -n syh62758_bl)
[[ $MODULE != "(builtin)" && -f $MODULE ]] || {
	echo "cannot locate the installed SYH62758 module: $MODULE" >&2
	exit 1
}
VERMAGIC=$(modinfo -F vermagic "$STAGE/syh62758_bl.ko")
[[ $VERMAGIC == "$KREL "* ]] || {
	echo "module vermagic mismatch: $VERMAGIC (running $KREL)" >&2
	exit 1
}

STAMP=$(date -u +%Y%m%d-%H%M%S)
BACKUP=/root/matepad-resume-fixes-backup-$STAMP
install -d -m 0700 "$BACKUP"
backup_one() {
	local path=$1
	if [[ -e $path ]]; then
		mkdir -p "$BACKUP$(dirname "$path")"
		cp -a "$path" "$BACKUP$path"
	fi
}

FILES=(
	/usr/local/sbin/matepad-sensord
	/usr/local/sbin/matepad-panelbacklightd
	/usr/local/sbin/matepad-sensor-recover
	/usr/lib/systemd/system-sleep/matepad-sensors
	/usr/lib/systemd/system-sleep/matepad-backlight
	/etc/systemd/system/matepad-panelbacklightd.service
	"$MODULE"
	/var/lib/matepad/panel-brightness
)
for f in "${FILES[@]}"; do backup_one "$f"; done
cp -a /var/lib/systemd/backlight "$BACKUP/var-lib-systemd-backlight" 2>/dev/null || true

# The old follower kept the last chosen value only in process memory. Preserve
# the last logged nonzero DPMS value before replacing it; otherwise use systemd's
# saved value, current hardware value, then the driver's documented default.
STATE=/var/lib/matepad/panel-brightness
if [[ ! -s $STATE ]]; then
	CURRENT=$(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || true)
	PANEL_ON=0
	for dpms in /sys/class/drm/card*-DSI-1/dpms; do
		if [[ -r $dpms ]] && [[ $(cat "$dpms") == On ]]; then
			PANEL_ON=1
			break
		fi
	done
	# If the display is currently on, its live slider value is the freshest
	# user choice. Only fall back to the old daemon's logs when the panel is dark.
	if [[ $PANEL_ON == 1 && $CURRENT =~ ^[1-9][0-9]*$ ]]; then
		VALUE=$CURRENT
	else
		VALUE=$(journalctl -b -u matepad-panelbacklightd.service --no-pager -o cat 2>/dev/null |
			sed -n 's/.*panel off -> backlight off (saved \([0-9][0-9]*\)).*/\1/p' | tail -n 1)
	fi
	if [[ ! $VALUE =~ ^[1-9][0-9]*$ ]]; then
		for f in $(ls -t /var/lib/systemd/backlight/*:backlight:panel0-backlight 2>/dev/null || true); do
			VALUE=$(cat "$f" 2>/dev/null || true)
			[[ $VALUE =~ ^[1-9][0-9]*$ ]] && break
		done
	fi
	if [[ ! $VALUE =~ ^[1-9][0-9]*$ ]]; then
		VALUE=$CURRENT
	fi
	[[ $VALUE =~ ^[1-9][0-9]*$ ]] || VALUE=115
	install -d -m 0755 /var/lib/matepad
	printf '%s\n' "$VALUE" > "$STATE"
	chmod 0644 "$STATE"
	chown root:root "$STATE"
	echo "seeded persistent backlight value: $VALUE"
fi

install -Dm0755 "$STAGE/matepad-sensord" /usr/local/sbin/matepad-sensord
install -Dm0755 "$STAGE/matepad-panelbacklightd" /usr/local/sbin/matepad-panelbacklightd
install -Dm0755 "$STAGE/matepad-sensor-recover" /usr/local/sbin/matepad-sensor-recover
install -Dm0644 "$STAGE/matepad-panelbacklightd.service" /etc/systemd/system/matepad-panelbacklightd.service
install -Dm0644 "$STAGE/syh62758_bl.ko" "$MODULE"
depmod -a "$KREL"
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/matepad-panelbacklightd.service
systemctl enable matepad-panelbacklightd.service >/dev/null
systemctl restart matepad-panelbacklightd.service

# Restart only the sensor D-Bus service so the running process gains the
# suspend protocol. Its clients use NameOwnerChanged and re-claim automatically.
SINCE=$(date --iso-8601=seconds)
systemctl restart matepad-sensord.service
for _ in $(seq 1 100); do
	if journalctl -b -u matepad-sensord --since "$SINCE" --no-pager -o cat 2>/dev/null |
		grep -q 'net.hadess.SensorProxy ready'; then
		break
	fi
	sleep 0.1
done
systemctl is-active --quiet matepad-sensord.service

# Install the signal hook only after the running daemon understands USR1/USR2.
install -Dm0755 "$STAGE/matepad-system-sleep-sensors" /usr/lib/systemd/system-sleep/matepad-sensors
install -Dm0755 "$STAGE/matepad-system-sleep-backlight" /usr/lib/systemd/system-sleep/matepad-backlight
systemctl daemon-reload

echo "Installed; backup: $BACKUP"
echo "Kernel module is staged at $MODULE; reboot to load it. No partition was written."
systemctl --no-pager --full status matepad-panelbacklightd matepad-sensord | sed -n '1,35p'
