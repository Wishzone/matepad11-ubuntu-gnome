#!/bin/bash
# Download/extract the rootless build tools into tools/.
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
T=$PROJ/tools
mkdir -p "$T"

download_extract() {	# download_extract PACKAGE DEST
	local pkg=$1 dest=$2 deb
	(cd "$T" && apt-get download "$pkg" >/dev/null 2>&1) || {
		echo "cannot download $pkg (apt lists missing? run apt-get update on the host)" >&2
		return 1
	}
	deb=$(ls -t "$T/${pkg}_"*.deb 2>/dev/null | head -1)
	[ -n "$deb" ] || { echo "no .deb for $pkg" >&2; return 1; }
	dpkg-deb -x "$deb" "$dest"
}

if [ ! -x "$T/debootstrap/usr/sbin/debootstrap" ]; then
	echo "== debootstrap"
	download_extract debootstrap "$T/debootstrap"
fi

if [ ! -x "$T/qemu/root/usr/bin/qemu-aarch64" ]; then
	echo "== qemu-user (static aarch64 interpreter)"
	download_extract qemu-user "$T/qemu-pkg"
	mkdir -p "$T/qemu/root/usr/bin"
	cp "$T/qemu-pkg/usr/bin/qemu-aarch64" "$T/qemu/root/usr/bin/qemu-aarch64"
	chmod 755 "$T/qemu/root/usr/bin/qemu-aarch64"
fi

# arm64 fakeroot: apt-get download on an amd64 host cannot select the arm64
# package, so fetch it from the ports pool directly.
FAKEROOT_VERSION=${FAKEROOT_VERSION:-1.37.2-1}
if [ ! -f "$T/fakeroot_${FAKEROOT_VERSION}_arm64.deb" ]; then
	echo "== fakeroot arm64 $FAKEROOT_VERSION"
	for base in \
		http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports \
		http://ports.ubuntu.com/ubuntu-ports; do
		if curl -fsSL --max-time 120 \
			"$base/pool/main/f/fakeroot/fakeroot_${FAKEROOT_VERSION}_arm64.deb" \
			-o "$T/fakeroot_${FAKEROOT_VERSION}_arm64.deb"; then
			break
		fi
	done
fi
if [ ! -f "$T/libfakeroot_${FAKEROOT_VERSION}_arm64.deb" ]; then
	for base in \
		http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports \
		http://ports.ubuntu.com/ubuntu-ports; do
		if curl -fsSL --max-time 120 \
			"$base/pool/main/f/fakeroot/libfakeroot_${FAKEROOT_VERSION}_arm64.deb" \
			-o "$T/libfakeroot_${FAKEROOT_VERSION}_arm64.deb"; then
			break
		fi
	done
fi
[ -s "$T/fakeroot_${FAKEROOT_VERSION}_arm64.deb" ] || {
	echo "fakeroot arm64 package missing; set FAKEROOT_VERSION" >&2; exit 1; }
[ -s "$T/libfakeroot_${FAKEROOT_VERSION}_arm64.deb" ] || {
	echo "libfakeroot arm64 package missing; set FAKEROOT_VERSION" >&2; exit 1; }

# Optional: QEMU system emulation for the smoke test. Its shared libraries are
# extracted here too, so the test does not need a host qemu-system package.
if [ ! -x "$T/qemu-system/usr/bin/qemu-system-aarch64" ]; then
	echo "== qemu-system-arm + libraries"
	download_extract qemu-system-arm "$T/qemu-system" || true
	for p in libpmem1 libfdt1 librdmacm1t64 libslirp0 libaio1t64 libndctl6 libdaxctl1; do
		download_extract "$p" "$T/qemu-system" || true
	done
fi

# dtc is only needed for scripts/patch-dtb.sh; prefer the host program.
if ! command -v dtc >/dev/null 2>&1 && [ ! -x "$T/dtc/usr/bin/dtc" ]; then
	echo "== device-tree-compiler (host dtc not found)"
	download_extract device-tree-compiler "$T/dtc" || true
fi

echo "tools ready under $T"
ls -l "$T/debootstrap/usr/sbin/debootstrap" "$T/qemu/root/usr/bin/qemu-aarch64" \
      "$T/fakeroot_${FAKEROOT_VERSION}_arm64.deb" 2>/dev/null
