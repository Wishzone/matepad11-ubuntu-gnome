#!/bin/sh
# /usr/local/bin/matepad-smoke-test: read-only pass/fail checks on the tablet.
# Run as root in the GNOME session (or over SSH with XDG_RUNTIME_DIR set for
# the GPU checks). It never changes hardware state.
set -u
pass=0 fail=0
ok() { printf 'PASS  %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

check "Ubuntu 26.04" "grep -q 'VERSION_ID=\"26.04\"' /etc/os-release"
check "no failed systemd unit" "[ -z \"\$(systemctl --failed --no-legend --plain 2>/dev/null)\" ]"
check "GDM active" "systemctl -q is-active gdm.service"
check "GNOME Shell process" "pgrep -x gnome-shell >/dev/null"
check "Wayland session" "loginctl show-session \"\$(loginctl show-seat seat0 -p ActiveSession --value)\" -p Type --value 2>/dev/null | grep -qx wayland"
check "DSI panel connected" "grep -qx connected /sys/class/drm/card*-DSI-1/status"
check "backlight panel0-backlight" "[ -w /sys/class/backlight/panel0-backlight/brightness ]"
check "panel brightness nonzero" "[ \"\$(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || echo 0)\" -gt 0 ]"
check "freedreno DRI" "ls /usr/lib/aarch64-linux-gnu/dri/msm_dri.so >/dev/null 2>&1"
check "freedreno Vulkan" "ls /usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so >/dev/null 2>&1"
SESSION_USER=$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null |
	xargs -r loginctl show-session -p Name --value 2>/dev/null)
[ -n "$SESSION_USER" ] || SESSION_USER=$(id -un 1000 2>/dev/null || echo user)
if have eglinfo; then
	check "EGL/OpenGL freedreno FD650" \
		"runuser -u '$SESSION_USER' -- env XDG_RUNTIME_DIR=/run/user/$(id -u "$SESSION_USER") WAYLAND_DISPLAY=wayland-0 eglinfo -B 2>/dev/null | grep -qi freedreno"
fi
if have vulkaninfo; then
	check "Vulkan Adreno" "runuser -u '$SESSION_USER' -- env XDG_RUNTIME_DIR=/run/user/$(id -u "$SESSION_USER") WAYLAND_DISPLAY=wayland-0 vulkaninfo --summary 2>/dev/null | grep -qi adreno"
fi
check "touch input device" "libinput list-devices 2>/dev/null | grep -qi -E 'touch|novatek|huawei'"
check "MatePad touch gesture filter" "systemctl -q is-active matepad-touch-rightclick.service && grep -q 'Name=\"MatePad Touch Right Click\"' /proc/bus/input/devices"
check "MatePad filtered touch gestures" "systemctl -q is-active matepad-touch-rightclick.service && grep -q 'Name=\"MatePad Touch Right Click\"' /proc/bus/input/devices"
check "pen input device" "libinput list-devices 2>/dev/null | grep -qi -E 'pen|stylus'"
check "linux70-touch active" "systemctl -q is-active linux70-touch.service"
check "Wi-Fi interface" "ip link show wlp1s0 >/dev/null 2>&1 || iw dev 2>/dev/null | grep -q Interface"
check "Bluetooth adapter" "bluetoothctl show 2>/dev/null | grep -q 'Controller'"
check "ALSA card" "grep -q 'HuaweiMatePad11' /proc/asound/cards"
check "PipeWire running" "pgrep -x pipewire >/dev/null"
check "WirePlumber running" "pgrep -x wireplumber >/dev/null"
check "battery present" "[ -e /sys/class/power_supply/battery/capacity ]"
check "charger present" "[ -e /sys/class/power_supply/matepad-charger/online ]"
check "sensors D-Bus name" "busctl --system list 2>/dev/null | grep -q net.hadess.SensorProxy"
check "SYH62758 module loaded" "lsmod | grep -q syh62758_bl"
check "DPMS backlight follower" "systemctl -q is-active matepad-panelbacklightd.service"
check "persistent panel brightness seeded" "[ -s /var/lib/matepad/panel-brightness ] && [ \"\$(cat /var/lib/matepad/panel-brightness)\" -gt 0 ]"
check "backlight sleep hook installed" "[ -x /usr/lib/systemd/system-sleep/matepad-backlight ]"
check "sensor sleep hook installed" "[ -x /usr/lib/systemd/system-sleep/matepad-sensors ]"
check "sensor sleep handshake active in daemon" "strings /usr/local/sbin/matepad-sensord | grep -q 'sensor stream paused before system sleep'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
