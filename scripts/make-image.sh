#!/bin/bash
# Build the flashable ext4 root image for the DBY-W09 GNOME port.
#
# The image is a bare ext4 filesystem with label LINUX70ROOT, exactly what the
# MatePad installer writes into the card's first partition (it grows it to the
# card and copies the tablet's own firmware/vendor files in). No partition
# table and no Huawei files are included.
#
# Usage: scripts/make-image.sh [--root DIR] [--out DIR] [--size 8G]
#                              [--keep-cache] [--no-xz]
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$PROJ/build/rootfs
OUT=$PROJ/build/out
SIZE=8G
KEEP_CACHE=0
DO_XZ=1
while [ $# -gt 0 ]; do
	case "$1" in
	--root) ROOT=$(realpath "$2"); shift 2 ;;
	--out) OUT=$2; shift 2 ;;
	--size) SIZE=$2; shift 2 ;;
	--keep-cache) KEEP_CACHE=1; shift ;;
	--no-xz) DO_XZ=0; shift ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done
[ -f "$ROOT/etc/os-release" ] || { echo "not a rootfs: $ROOT" >&2; exit 1; }
grep -q '^VERSION_ID="26.04"' "$ROOT/etc/os-release" || {
	echo "refusing: rootfs is not Ubuntu 26.04" >&2; exit 1; }
[ -x "$ROOT/usr/bin/gnome-shell" ] || { echo "refusing: no gnome-shell in rootfs" >&2; exit 1; }
[ -f "$ROOT/usr/lib/matepad/linux-boot/SHA256SUMS" ] || {
	echo "refusing: no MatePad boot bundle in rootfs" >&2; exit 1; }
[ -f "$ROOT/usr/share/matepad/device-files/firmware.txt" ] || {
	echo "refusing: no device-files lists (the installer needs them)" >&2; exit 1; }

WORK=$PROJ/build/image-work
STAMP=$(date -u +%Y%m%d)
NAME=ubuntu-26.04-gnome-dby-w09-$STAMP
IMG=$WORK/$NAME.img
MANIFEST=$WORK/ownership.tsv
mkdir -p "$WORK" "$OUT"

# No build-only pieces in the shipped image, including proot artifacts.
rm -f "$ROOT/usr/bin/qemu-aarch64-static" "$ROOT/var/lib/matepad-fakeroot.state" \
      "$ROOT/etc/ld.so.preload"
rm -rf "$ROOT/tmp/matepad-src" "$ROOT/tmp/hexagonrpc" "$ROOT/host-rootfs"
mkdir -p "$ROOT/tmp" "$ROOT/var/lib/matepad" "$ROOT/etc/matepad"
chmod 1777 "$ROOT/tmp"
# Do not restore a systemd-resolved symlink: Ubuntu 26.04's package set used
# here does not ship the resolved unit. finalize.sh writes a plain file that
# NetworkManager updates on association.

# Record the package versions before the cache is removed.
dpkg-query --admindir="$ROOT/var/lib/dpkg" -W -f '${Package}\t${Version}\n' \
	> "$OUT/$NAME.packages"

# Build the ownership manifest while the .debs are still cached. A resumed
# build may already have removed the cache; the manifest from that run is
# still valid because it was generated before the cleanup.
if [ -d "$ROOT/var/cache/apt/archives" ] && [ -n "$(ls -A "$ROOT/var/cache/apt/archives" 2>/dev/null)" ]; then
	"$PROJ/scripts/gen-ownership.py" "$ROOT" "$ROOT/var/cache/apt/archives" "$MANIFEST"
elif [ ! -s "$MANIFEST" ]; then
	echo "error: apt cache is empty and no ownership manifest exists at $MANIFEST" >&2
	exit 1
else
	echo "using existing ownership manifest: $MANIFEST"
fi

if [ "$KEEP_CACHE" = 0 ]; then
	rm -rf "$ROOT/var/cache/apt/archives" "$ROOT/var/lib/apt/lists"
fi
rm -rf "$ROOT/var/tmp"/* "$ROOT/tmp"/* 2>/dev/null || true

# Apply fake ownership + the package modes, then let mke2fs read the tree
# through the same fakeroot daemon.
	echo "building $IMG ($SIZE)"
rm -f "$IMG"
(
	export FAKEROOTDONTTRYCHOWN=1
	fakeroot -s "$WORK/fakeroot.state" -- bash -c '
		set -e
		chown -R 0:0 "$0"
		while IFS=$'"'"'\t'"'"' read -r mode uid gid typ rel; do
			p="$0/$rel"
			[ -e "$p" ] || [ -L "$p" ] || continue
			chown -h "$uid:$gid" "$p"
			[ "$typ" = l ] || chmod "$mode" "$p"
		done < "$1"
		truncate -s "$2" "$3"
		mkfs.ext4 -q -F -L LINUX70ROOT -O ^orphan_file,^metadata_csum_seed \
			-E root_owner=0:0 -d "$0" "$3"
	' "$ROOT" "$MANIFEST" "$SIZE" "$IMG"
)

e2fsck -fy "$IMG" >/dev/null
resize2fs -M "$IMG" >/dev/null
blocks=$(dumpe2fs -h "$IMG" 2>/dev/null | sed -n 's/^Block count: *//p')
truncate -s $(( blocks * 4096 + 2048 * 1024 * 1024 )) "$IMG"
resize2fs "$IMG" >/dev/null
e2fsck -fy "$IMG" >/dev/null

# Inspect the result without mounting it.
debugfs -R 'stat /usr/bin/sudo' "$IMG" 2>/dev/null | sed -n '1,4p'
debugfs -R 'stat /usr/lib/dbus-1.0/dbus-daemon-launch-helper' "$IMG" 2>/dev/null | sed -n '1,4p'
stat -c %s "$IMG" > "$OUT/$NAME.img.size"
if [ "$DO_XZ" = 1 ]; then
	xz -9 -T0 --memlimit-compress=40% -c "$IMG" > "$OUT/$NAME.img.xz"
	(cd "$OUT" && sha256sum "$NAME.img.xz" > "$NAME.img.xz.sha256")
	echo "output: $OUT/$NAME.img.xz"
	ls -lh "$OUT/$NAME.img.xz"
else
	cp "$IMG" "$OUT/$NAME.img"
	echo "output: $OUT/$NAME.img"
fi
