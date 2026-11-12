#!/bin/sh
# /usr/local/bin/matepad-collect-logs: gather the evidence for a DBY-W09 test
# run into /tmp/matepad-logs-<timestamp>.tar.gz. Run as root on the tablet.
set -u
OUT=/tmp/matepad-logs-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
log() { echo "== $*" >> "$OUT/commands.log"; "$@" >> "$OUT/commands.log" 2>&1 || true; }

exec > "$OUT/console.log" 2>&1
echo "MatePad DBY-W09 log collection $(date -u)"
echo "kernel: $(uname -a)"
echo "rootfs: $(cat /etc/os-release 2>/dev/null | tr '\n' ' ')"

log uname -a
log cat /proc/cmdline
log cat /proc/version
log cat /proc/device-tree/model
log findmnt -no SOURCE,FSTYPE,OPTIONS /
log lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
log df -h
log free -h
log systemctl --failed --no-pager
log systemctl get-default
log systemctl status gdm3 NetworkManager bluetooth ssh --no-pager
log systemctl status linux70-touch hexagonrpcd-sdsp matepad-sensord --no-pager
log systemctl status matepad-tfa9874 matepad-volkeys matepad-panelbacklightd --no-pager
log systemctl status matepad-touch-rightclick --no-pager
log systemctl status matepad-modules matepad-device-setup --no-pager
log systemctl status systemd-backlight@backlight:panel0-backlight matepad-sensor-recover --no-pager
log journalctl -b --no-pager
log dmesg
log lsmod
log cat /proc/interrupts
log cat /proc/config.gz

log sh -c 'for d in /sys/class/drm/card*-DSI-1; do echo $d; cat $d/status $d/modes $d/dpms 2>/dev/null; done'
log sh -c 'for b in /sys/class/backlight/*; do echo $b; cat $b/max_brightness $b/brightness; done'
log sh -c 'cat /var/lib/matepad/panel-brightness 2>/dev/null; for b in /var/lib/systemd/backlight/*:backlight:panel0-backlight; do echo $b; cat $b; done'
log sh -c 'ls -l /sys/class/drm /sys/class/backlight'
log sh -c 'cat /sys/kernel/debug/dri/*/state 2>/dev/null | head -200'

log sh -c 'command -v libinput >/dev/null && libinput list-devices || true'
log sh -c 'cat /proc/bus/input/devices'
log cat /sys/touchscreen/touch_chip_info 2>/dev/null

log sh -c 'aplay -l; arecord -l'
log sh -c 'command -v wpctl >/dev/null && wpctl status || true'
log sh -c 'journalctl --user -u pipewire -u wireplumber --no-pager | tail -300'
log sh -c 'cat /proc/asound/cards /proc/asound/modules'

log sh -c 'nmcli device status; nmcli -f GENERAL,WIFI-PROPERTIES dev show 2>/dev/null | head -80'
log sh -c 'ip addr; ip route'
log sh -c 'ls -l /sys/class/net; for n in /sys/class/net/*; do echo $n; cat $n/address 2>/dev/null; done'
log sh -c 'journalctl -b -u NetworkManager --no-pager | tail -300'
log sh -c 'dmesg | grep -i -E "ath11k|brcm|firmware"'
log sh -c 'bluetoothctl show 2>/dev/null; bluetoothctl devices 2>/dev/null'
log sh -c 'journalctl -b -u bluetooth --no-pager | tail -200'

log sh -c 'upower -i /org/freedesktop/UPower/devices/battery_battery'
log sh -c 'for p in /sys/class/power_supply/*; do echo $p; cat $p/type $p/status $p/capacity $p/voltage_now 2>/dev/null; done'
log sh -c 'cat /sys/kernel/wakeup_reasons/last_resume_reason 2>/dev/null; cat /sys/power/state'
log sh -c 'journalctl -b -u systemd-suspend --no-pager | tail -100'

log sh -c 'lsusb; lspci -nn'
log sh -c 'for p in /sys/class/typec/port*; do echo $p; cat $p/data_role $p/power_role 2>/dev/null; done'
log sh -c 'for p in /sys/class/drm/card*-DP-*; do echo $p; cat $p/status 2>/dev/null; done'
log sh -c 'hwclock -r 2>&1; timedatectl'

log sh -c 'ls -l /usr/lib/matepad/linux-boot; cat /usr/lib/matepad/linux-boot/release.txt'
log sh -c 'ls -l /usr/lib/modules; find /usr/lib/modules -maxdepth 2 -name "syh62758_bl.ko" -o -name "hexagonrpcd" 2>/dev/null'
log sh -c 'dpkg-query -W -f="\${Package} \${Version}\n" | grep -E "gnome-shell|gdm3|ubuntu-desktop|mesa|pipewire|wireplumber|linux-firmware|bluez|systemd"'

tar -C /tmp -czf "$OUT.tar.gz" "$(basename "$OUT")"
echo "wrote $OUT.tar.gz"
