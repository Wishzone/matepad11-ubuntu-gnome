#!/bin/bash
# Non-destructive checks on the built ext4 image (no mounting, no root).
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
IMG=${1:-$(ls -t "$PROJ"/build/out/ubuntu-26.04-gnome-dby-w09-*.img 2>/dev/null | head -1 || true)}
[ -f "$IMG" ] || { echo "no image; run scripts/make-image.sh --no-xz" >&2; exit 1; }
fail=0
chk() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
statimg() { debugfs -R "stat $1" "$IMG" 2>/dev/null; }

echo "image: $IMG"
chk "label LINUX70ROOT" "dumpe2fs -h '$IMG' 2>/dev/null | grep -q 'Filesystem volume name:.*LINUX70ROOT'"
chk "no orphan_file / metadata_csum_seed" "! dumpe2fs -h '$IMG' 2>/dev/null | grep -qE 'orphan_file|metadata_csum_seed'"
chk "os-release 26.04" "debugfs -R 'cat /usr/lib/os-release' '$IMG' 2>/dev/null | grep -q 'VERSION_ID=\"26.04\"'"
chk "GNOME Shell binary" "debugfs -R 'stat /usr/bin/gnome-shell' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755'"
chk "GDM binary" "debugfs -R 'stat /usr/sbin/gdm3' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755'"
chk "Ubuntu Sans Mono font" "debugfs -R 'stat /usr/share/fonts/truetype/ubuntu/UbuntuSansMono[wght].ttf' '$IMG' 2>/dev/null | grep -q 'Mode:.*0644'"
chk "MatePad gesture daemon" "debugfs -R 'stat /usr/local/sbin/matepad-touch-rightclick' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755'"
chk "MatePad gesture service" "debugfs -R 'stat /etc/systemd/system/matepad-touch-rightclick.service' '$IMG' 2>/dev/null | grep -q 'Mode:.*0644'"
chk "MatePad gesture coordinate config" "debugfs -R 'cat /etc/matepad-touch-rightclick.conf' '$IMG' 2>/dev/null | grep -q 'SCREEN_WIDTH=1280'"
chk "boot bundle Image.gz" "debugfs -R 'stat /usr/lib/matepad/linux-boot/Image.gz' '$IMG' 2>/dev/null | grep -q 'Mode:.*0644'"
chk "device-files firmware list" "debugfs -R 'stat /usr/share/matepad/device-files/firmware.txt' '$IMG' 2>/dev/null | grep -q 'Mode:.*0644'"
chk "SYH62758 module" "debugfs -R 'stat /usr/lib/modules/7.0.14-dby-w09/extra/syh62758_bl.ko' '$IMG' 2>/dev/null | grep -q 'Mode:.*0644'"
chk "backlight persistence service" "debugfs -R 'cat /etc/systemd/system/matepad-panelbacklightd.service' '$IMG' 2>/dev/null | grep -q 'StateDirectory=matepad'"
chk "backlight suspend hook" "debugfs -R 'stat /usr/lib/systemd/system-sleep/matepad-backlight' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755'"
chk "sensor suspend hook" "debugfs -R 'stat /usr/lib/systemd/system-sleep/matepad-sensors' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755'"
chk "sensor resume delegates FastRPC startup to udev" "debugfs -R 'cat /usr/lib/systemd/system-sleep/matepad-sensors' '$IMG' 2>/dev/null | grep -q 'udev rule starts HEXAGON_UNIT'"
chk "sensor pause protocol in daemon" "debugfs -R 'cat /usr/local/sbin/matepad-sensord' '$IMG' 2>/dev/null | strings | grep -q 'sensor stream paused before system sleep'"
chk "hexagonrpcd" "debugfs -R 'stat /usr/local/bin/hexagonrpcd' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755'"
chk "sudo setuid 4755" "statimg /usr/bin/sudo.ws | grep -q 'Mode:.*04755'"
chk "passwd setuid 4755" "statimg /usr/bin/passwd | grep -q 'Mode:.*04755'"
chk "pkexec setuid 4755" "statimg /usr/bin/pkexec | grep -q 'Mode:.*04755'"
chk "ssh-agent setgid root:_ssh" "statimg /usr/bin/ssh-agent | grep -qE 'Mode:.*02755' && statimg /usr/bin/ssh-agent | grep -q 'Group: *102'"
chk "dbus helper 4754 root:messagebus" "statimg /usr/lib/dbus-1.0/dbus-daemon-launch-helper | grep -q 'Mode:.*04754' && statimg /usr/lib/dbus-1.0/dbus-daemon-launch-helper | grep -qE 'Group: *99[0-9]'"
chk "shadow 0640 root:shadow" "statimg /etc/shadow | grep -q 'Mode:.*0640' && statimg /etc/shadow | grep -q 'Group: *42'"
chk "plain resolv.conf (no dangling resolved link)" "statimg /etc/resolv.conf | grep -q 'Type: regular'"
chk "log/smoke-test helpers" "debugfs -R 'stat /usr/local/bin/matepad-smoke-test' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755' && debugfs -R 'stat /usr/local/bin/matepad-collect-logs' '$IMG' 2>/dev/null | grep -q 'Mode:.*0755'"
chk "no qemu-aarch64-static in image" "! debugfs -R 'stat /usr/bin/qemu-aarch64-static' '$IMG' 2>/dev/null | grep -q 'Inode:'"
chk "no fakeroot state in image" "! debugfs -R 'stat /var/lib/matepad-fakeroot.state' '$IMG' 2>/dev/null | grep -q 'Inode:'"
chk "no KDE plasma-desktop" "! debugfs -R 'cat /var/lib/dpkg/status' '$IMG' 2>/dev/null | grep -q '^Package: plasma-desktop$'"
chk "no snapd" "! debugfs -R 'cat /var/lib/dpkg/status' '$IMG' 2>/dev/null | grep -q '^Package: snapd$'"

if [ "$fail" = 0 ]; then
	echo "PASS"
else
	echo "one or more checks failed" >&2
	exit 1
fi
