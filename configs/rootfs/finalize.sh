#!/bin/bash
# Final userspace configuration of the Ubuntu 26.04 GNOME rootfs.
# Run through scripts/rootfs-chroot.sh.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

echo "matepad" > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1	localhost
127.0.1.1	matepad
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

# The installer writes the ext4 image with this label and grows it at first
# boot; no partition UUID is assumed.
cat > /etc/fstab <<'EOF'
LABEL=LINUX70ROOT	/	ext4	defaults,noatime	0 1
EOF

# Locales used by the installer's language choices and by the build.
for l in en_US.UTF-8 zh_CN.UTF-8; do
	sed -i "s/^# *\(${l}[[:space:]]\+UTF-8\)/\1/" /etc/locale.gen
done
locale-gen
update-locale LANG=en_US.UTF-8

# GDM on Wayland (the only supported session on the Adreno 650 here).
mkdir -p /etc/gdm3
cat > /etc/gdm3/custom.conf <<'EOF'
[daemon]
WaylandEnable=true
AutomaticLoginEnable=false
EOF

# GNOME/logind defaults for a tablet. The cover is a lid switch; suspend on
# close is the expected behaviour. (The installer's autologin choice is
# translated by matepad-gdm-autologin.service.)
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/50-matepad.conf <<'EOF'
[Login]
HandlePowerKey=suspend
HandlePowerKeyLongPress=poweroff
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
EOF

# Resolver: Ubuntu 26.04 does not ship the systemd-resolved unit in this
# package set, so do not leave a dangling /etc/resolv.conf symlink. A plain
# file gives the first boot DNS; NetworkManager rewrites it on association.
rm -f /etc/resolv.conf
cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Ubuntu 26.04 ships sudo-rs as an alternative. The installer and the test
# instructions use classic sudo; select it if present.
if [ -x /usr/bin/sudo.ws ]; then
	update-alternatives --set sudo /usr/bin/sudo.ws >/dev/null 2>&1 || true
fi

# Build-only files and proot artifacts (`host-rootfs`, `ld.so.preload`).
rm -f /usr/sbin/policy-rc.d /etc/apt/apt.conf.d/99-root-sandbox
rm -f /etc/ld.so.preload
rm -rf /host-rootfs
rm -rf /tmp/matepad-src /tmp/hexagonrpc /tmp/*.sh /tmp/*.py
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id

# The kernel bundle and modules are already in /usr/lib; refresh the module
# dependency databases for the exact kernel release.
KREL=$(cat /usr/lib/matepad/linux-boot/release.txt 2>/dev/null || true)
if [ -n "$KREL" ] && [ -d "/usr/lib/modules/$KREL" ]; then
	depmod -a "$KREL"
fi

# GNOME needs a writable /var/lib/matepad for first-boot stamps.
install -d -m 755 /var/lib/matepad /etc/matepad /usr/share/matepad

# Keep the installed kernel and the boot bundle in sync with the checksums.
if [ -f /usr/lib/matepad/linux-boot/SHA256SUMS ]; then
	(cd /usr/lib/matepad/linux-boot && sha256sum -c SHA256SUMS)
fi

echo "rootfs finalized: $(cat /etc/os-release | sed -n 's/^PRETTY_NAME=//p')"
