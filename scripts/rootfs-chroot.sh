#!/bin/bash
# Run a command as fake root in the arm64 rootfs, using a user namespace +
# binfmt_misc (qemu-aarch64-static), with a minimal /dev and a fresh /proc.
# No host root, no proot. Usage: scripts/rootfs-chroot.sh COMMAND [ARG...]
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
ROOT=${ROOT:-$PROJ/build/rootfs}
QEMU=${QEMU:-$PROJ/tools/qemu/root/usr/bin/qemu-aarch64}
if [ "${1:-}" != "--inner" ]; then
	exec unshare --user --map-root-user --mount --pid --fork "$0" --inner "$@"
fi
shift
install -D -m 0755 "$QEMU" "$ROOT/usr/bin/qemu-aarch64-static"
mkdir -p /tmp/matepad-binfmt
mount -t binfmt_misc binfmt_misc /tmp/matepad-binfmt 2>/dev/null || true
if [ ! -e /tmp/matepad-binfmt/qemu-aarch64 ]; then
	python3 - <<'PY'
import os
cfg=(b':qemu-aarch64:M::\\x7f\\x45\\x4c\\x46\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00'
     b'\\x00\\x00\\x00\\x00\\x02\\x00\\xb7\\x00:'
     b'\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\x00\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff'
     b'\\xfe\\xff\\xff\\xff:/usr/bin/qemu-aarch64-static:\n')
fd=os.open('/tmp/matepad-binfmt/register', os.O_WRONLY)
os.write(fd, cfg)
os.close(fd)
PY
fi
mount -t tmpfs tmpfs "$ROOT/dev"
for n in null zero full random urandom tty ptmx; do
	: > "$ROOT/dev/$n"
	mount --bind "/dev/$n" "$ROOT/dev/$n" 2>/dev/null || true
done
if ! ( : > "$ROOT/dev/null" ) 2>/dev/null; then
	umount "$ROOT/dev/null" 2>/dev/null || true
	: > "$ROOT/dev/null"
fi
mkdir -p "$ROOT/dev/pts"
mount --bind /dev/pts "$ROOT/dev/pts" 2>/dev/null || true
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys" 2>/dev/null || true
exec /usr/bin/chroot "$ROOT" "$@"
