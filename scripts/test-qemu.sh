#!/bin/bash
# Boot the built image in QEMU with the DBY kernel. This validates the rootfs,
# systemd and the staged services; it cannot validate the panel/GPU/touch
# because the DBY kernel has no virtio-gpu.
#
# Usage: scripts/test-qemu.sh [IMAGE] [SECONDS]
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
IMG=${1:-$(ls -t "$PROJ"/build/out/ubuntu-26.04-gnome-dby-w09-*.img 2>/dev/null | head -1 || true)}
SECS=${2:-100}
[ -f "$IMG" ] || { echo "no image; run scripts/make-image.sh --no-xz" >&2; exit 1; }

Q=$PROJ/tools/qemu-system/usr/bin/qemu-system-aarch64
[ -x "$Q" ] || { echo "missing qemu-system; run scripts/prepare-host-tools.sh" >&2; exit 1; }
export LD_LIBRARY_PATH=$PROJ/tools/qemu-system/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
mkdir -p "$PROJ/build/qemu" "$PROJ/build/logs"
if [ ! -s "$PROJ/build/qemu/Image" ]; then
	gunzip -c "$PROJ/build/rootfs/usr/lib/matepad/linux-boot/Image.gz" > "$PROJ/build/qemu/Image"
fi
LOG=$PROJ/build/logs/qemu-$(date +%Y%m%d-%H%M%S).log

set +e
timeout "$SECS" "$Q" -M virt -cpu cortex-a72 -smp 4 -m 4096 \
	-kernel "$PROJ/build/qemu/Image" \
	-drive file="$IMG",format=raw,if=virtio,cache=unsafe \
	-append "console=ttyAMA0 root=/dev/vda rw rootwait loglevel=5 systemd.unit=multi-user.target systemd.show_status=1" \
	-nographic -no-reboot -net none 2>&1 | tee "$LOG"
rc=$?
set -e
echo "log: $LOG (qemu rc=$rc)"
if grep -qa 'matepad login:' "$LOG" && ! grep -qa 'FAILED' "$LOG"; then
	echo "PASS: reached a login prompt with no FAILED unit"
	exit 0
fi
echo "FAIL: no clean login prompt (see $LOG)" >&2
exit 1
