#!/bin/bash
# Run a command in the arm64 rootfs as fake root, without host root.
# Uses proot + statically linked qemu-aarch64 (no binfmt registration needed).
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
ROOT=${ROOT:-$PROJ/build/rootfs}
QEMU=${QEMU:-$PROJ/tools/qemu/root/usr/bin/qemu-aarch64}
PROOT=${PROOT:-$PROJ/tools/proot/usr/bin/proot}
export PROOT_NO_SECCOMP=1
exec "$PROOT" -q "$QEMU" -0 -r "$ROOT" -b /dev -b /proc -b /sys -w /root "$@"
