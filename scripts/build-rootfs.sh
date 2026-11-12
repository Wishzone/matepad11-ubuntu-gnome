#!/bin/bash
# Build the Ubuntu 26.04 arm64 GNOME rootfs for the DBY-W09 without host root.
#
#   scripts/build-rootfs.sh --from-scratch \
#       --bundle ../recovery/current-linux-boot \
#       --modules ../recovery/current-modules-7.0.14-dby-w09.tar.gz
#
# The script is resumable: without --from-scratch it reuses build/rootfs and
# skips the bootstrap if /etc/os-release already exists. All package work is
# done in a user namespace with qemu-aarch64-static and fakeroot.
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$PROJ/build/rootfs
export ROOT
BUNDLE=$PROJ/../recovery/current-linux-boot
MODULES=$PROJ/../recovery/current-modules-7.0.14-dby-w09.tar.gz
MIRROR=http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports
FROM_SCRATCH=0
DO_IMAGE=0
while [ $# -gt 0 ]; do
	case "$1" in
	--from-scratch) FROM_SCRATCH=1; shift ;;
	--root) ROOT=$(realpath "$2"); shift 2 ;;
	--bundle) BUNDLE=$(realpath "$2"); shift 2 ;;
	--modules) MODULES=$(realpath "$2"); shift 2 ;;
	--mirror) MIRROR=$2; shift 2 ;;
	--image) DO_IMAGE=1; shift ;;
	-h|--help) sed -n '2,16p' "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done
[ -d "$BUNDLE" ] || { echo "missing boot bundle: $BUNDLE" >&2; exit 1; }
[ -f "$MODULES" ] || { echo "missing modules tarball: $MODULES" >&2; exit 1; }

T=$PROJ/tools
DEBOOTSTRAP=$T/debootstrap/usr/sbin/debootstrap
export DEBOOTSTRAP_DIR=$T/debootstrap/usr/share/debootstrap
QEMU=$T/qemu/root/usr/bin/qemu-aarch64
[ -x "$DEBOOTSTRAP" ] || { echo "run scripts/prepare-host-tools.sh first" >&2; exit 1; }
[ -x "$QEMU" ] || { echo "missing qemu-aarch64-static; run prepare-host-tools.sh" >&2; exit 1; }

log() { printf '\n== %s\n' "$*"; }

if [ "$FROM_SCRATCH" = 1 ]; then
	rm -rf "$ROOT"
fi
mkdir -p "$ROOT" "$PROJ/build/logs"

# ---- 1. debootstrap stage 1 ------------------------------------------------
if [ ! -f "$ROOT/etc/os-release" ]; then
	log "debootstrap stage 1 ($MIRROR)"
	rm -rf "$ROOT"/* "$ROOT"/.[!.]* 2>/dev/null || true
	unshare --user --map-root-user --mount --pid --fork bash -c '
		set -e
		export PATH="'"$T/debootstrap/usr/sbin"':$PATH"
		export DEBOOTSTRAP_DIR="'"$DEBOOTSTRAP_DIR"'"
		export TAR_OPTIONS=--no-same-owner
		debootstrap --arch=arm64 --foreign --variant=minbase \
			--components=main,universe \
			--include=ca-certificates,locales,gnupg,curl,apt-utils \
			resolute "'"$ROOT"'" "'"$MIRROR"'"
	' 2>&1 | tee "$PROJ/build/logs/debootstrap-stage1.log" | tail -5
fi

# ---- 2. debootstrap stage 2 ------------------------------------------------
# fakeroot is needed here: base-files' postinst chowns /var/mail to the
# unmapped group `mail`, and dpkg's own chown would fail in the user namespace.
mkdir -p "$ROOT/var/lib"
for d in "$T"/fakeroot_*_arm64.deb "$T"/libfakeroot_*_arm64.deb; do
	[ -f "$d" ] && dpkg-deb -x "$d" "$ROOT"
done
[ -e "$ROOT/usr/bin/fakeroot" ] || ln -s fakeroot-sysv "$ROOT/usr/bin/fakeroot"
if [ -d "$ROOT/debootstrap" ]; then
	# proot (not chroot) for this stage: debootstrap's dpkg invokes maintainer
	# scripts that chown to unmapped system groups. proot intercepts those
	# syscalls; a plain chroot cannot.
	log "debootstrap stage 2 (proot + qemu-aarch64)"
	rm -f "$ROOT/etc/resolv.conf"
	cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
	ROOT="$ROOT" DEBOOTSTRAP_DIR=/debootstrap \
		"$PROJ/scripts/rootfs-enter.sh" /debootstrap/debootstrap --second-stage \
		2>&1 | tee "$PROJ/build/logs/debootstrap-stage2.log" | tail -5
	rm -rf "$ROOT/debootstrap"
fi

# ---- 3. apt sources and fakeroot ------------------------------------------
log "apt sources and fakeroot"
install -D -m 644 "$PROJ/configs/apt/ubuntu.sources" "$ROOT/etc/apt/sources.list.d/ubuntu.sources"
rm -f "$ROOT/etc/apt/sources.list"
rm -f "$ROOT/etc/resolv.conf"
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
for d in "$T"/fakeroot_*_arm64.deb "$T"/libfakeroot_*_arm64.deb; do
	[ -f "$d" ] && dpkg-deb -x "$d" "$ROOT"
done
[ -e "$ROOT/usr/bin/fakeroot" ] || ln -s fakeroot-sysv "$ROOT/usr/bin/fakeroot"
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"
chmod 755 "$ROOT/usr/sbin/policy-rc.d"
printf 'APT::Sandbox::User "root";\n' > "$ROOT/etc/apt/apt.conf.d/99-root-sandbox"

# ---- 4. GNOME package set -------------------------------------------------
log "installing the GNOME package set (fakeroot)"
install -m 644 "$PROJ/configs/packages.list" "$ROOT/tmp/packages.list"
rm -rf "$ROOT/tmp/bluez"
if [ -d "$PROJ/overrides/bluez" ]; then
	install -d "$ROOT/tmp/bluez"
	cp "$PROJ"/overrides/bluez/*.deb "$ROOT/tmp/bluez/"
fi
cat > "$ROOT/tmp/install-packages.sh" <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 SYSTEMD_OFFLINE=1
APT="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
apt-get update
mapfile -t pkgs < /tmp/packages.list
# Strip comments/blank lines in the list.
pkgs=("${pkgs[@]}")
$APT --no-install-recommends install "${pkgs[@]}"
# The Huawei keyboard's HOG CCC read is rejected by the device; use the
# patched BlueZ build (same Ubuntu version, + the local patch).
if ls /tmp/bluez/*.deb >/dev/null 2>&1; then
	dpkg -i /tmp/bluez/*.deb
	apt-mark hold bluez libbluetooth3
fi
audit=$(dpkg --audit)
if [ -n "$audit" ]; then
	echo "$audit" >&2
	exit 1
fi
EOF
# Remove comments/blank lines so bash does not see them as package names.
sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$ROOT/tmp/packages.list" > "$ROOT/tmp/packages.list.clean"
mv "$ROOT/tmp/packages.list.clean" "$ROOT/tmp/packages.list"
"$PROJ/scripts/rootfs-chroot.sh" /bin/bash -c \
	'export FAKEROOTDONTTRYCHOWN=1; fakeroot -i /var/lib/matepad-fakeroot.state -s /var/lib/matepad-fakeroot.state -- /bin/bash /tmp/install-packages.sh' \
	2>&1 | tee "$PROJ/build/logs/install-packages.log" | tail -20

# ---- 5. compile helpers and hexagonrpc ------------------------------------
log "compiling the hardware helpers"
rm -rf "$ROOT/tmp/matepad-src" "$ROOT/tmp/hexagonrpc"
mkdir -p "$ROOT/tmp/matepad-src"
tar -C "$PROJ/upstream/kubuntu-dby-w09" --exclude=.git --exclude=screenshots -cf - . |
	tar -C "$ROOT/tmp/matepad-src" -xf -
install -D -m 0644 "$PROJ/overrides/touchscreen/matepad-touch-rightclick.c" \
	"$ROOT/tmp/matepad-src/touch/matepad-touch-rightclick.c"
install -D -m 0644 "$PROJ/overrides/upower/matepad-upower-sign.c" \
	"$ROOT/tmp/matepad-src/upower/matepad-upower-sign.c"
cp "$PROJ/configs/rootfs/build-tools.sh" "$ROOT/tmp/build-tools.sh"
"$PROJ/scripts/rootfs-chroot.sh" /bin/bash /tmp/build-tools.sh 2>&1 |
	tee "$PROJ/build/logs/build-tools.log" | tail -5

if [ -d "$PROJ/upstream/hexagonrpc" ]; then
	log "compiling hexagonrpcd"
	cp -a "$PROJ/upstream/hexagonrpc" "$ROOT/tmp/hexagonrpc"
	cp "$PROJ/configs/rootfs/build-hexagonrpc.sh" "$ROOT/tmp/build-hexagonrpc.sh"
	"$PROJ/scripts/rootfs-chroot.sh" /bin/bash /tmp/build-hexagonrpc.sh 2>&1 |
		tee "$PROJ/build/logs/build-hexagonrpc.log" | tail -5
fi

# ---- 6. kernel bundle, modules and device lists ---------------------------
log "installing the kernel bundle and modules"
KREL=$(cat "$BUNDLE/release.txt")
install -d "$ROOT/usr/lib/matepad/linux-boot" "$ROOT/usr/share/matepad/device-files" \
	"$ROOT/usr/lib/modules/$KREL"
for f in Image.gz sm8250-huawei-dby-w09.dtb dtbo.img ramdisk-payload.img cmdline.txt release.txt; do
	cp "$BUNDLE/$f" "$ROOT/usr/lib/matepad/linux-boot/"
done
# Local hardware adjustments: landscape rotation + SYH62758 backlight.
DTC=${DTC:-}; "$PROJ/scripts/patch-dtb.sh" \
	"$ROOT/usr/lib/matepad/linux-boot/sm8250-huawei-dby-w09.dtb" \
	"$ROOT/usr/lib/matepad/linux-boot/sm8250-huawei-dby-w09.dtb"
tar -xzf "$MODULES" -C "$ROOT/usr/lib/modules/$KREL"
install -m 644 "$PROJ/upstream/kubuntu-dby-w09/device-files/manifest.txt" \
   "$PROJ/upstream/kubuntu-dby-w09/device-files/firmware.txt" \
   "$ROOT/usr/share/matepad/device-files/"
(cd "$ROOT/usr/lib/matepad/linux-boot" &&
 sha256sum Image.gz sm8250-huawei-dby-w09.dtb dtbo.img ramdisk-payload.img cmdline.txt release.txt > SHA256SUMS)

# ---- 7. hardware services, GNOME integration, finalize -------------------
log "staging hardware services and GNOME integration"
R="$ROOT" "$PROJ/scripts/stage-hardware.sh"
cp "$PROJ/configs/rootfs/finalize.sh" "$ROOT/tmp/finalize.sh"
"$PROJ/scripts/rootfs-chroot.sh" /bin/bash /tmp/finalize.sh 2>&1 |
	tee "$PROJ/build/logs/finalize.log" | tail -5
cp "$PROJ/configs/rootfs/enable-services.sh" "$ROOT/tmp/enable-services.sh"
"$PROJ/scripts/rootfs-chroot.sh" /bin/bash /tmp/enable-services.sh 2>&1 |
	tee "$PROJ/build/logs/enable-services.log" | tail -8

log "rootfs ready at $ROOT"
if [ "$DO_IMAGE" = 1 ]; then
	"$PROJ/scripts/make-image.sh" --root "$ROOT"
fi
