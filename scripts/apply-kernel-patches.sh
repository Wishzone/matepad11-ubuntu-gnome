#!/bin/bash
# Apply the camera and audio patches to a Linux 7.0.14 source tree.
#
#   scripts/apply-kernel-patches.sh /path/to/linux-7.0.14
#
# The camera file replaces drivers/media/i2c/gc08a3.c; the audio patch is
# applied with patch(1).  Neither depends on the DBY board patches.
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
KSRC=${1:?usage: $0 /path/to/linux-7.0.14}

[ -f "$KSRC/Makefile" ] || {
	echo "no kernel source at $KSRC" >&2
	exit 1
}
[ -f "$KSRC/drivers/media/i2c/gc08a3.c" ] || {
	echo "$KSRC is not a Linux 7.0.y tree (no gc08a3.c)" >&2
	exit 1
}

install -m 644 "$PROJ/patches/camera/gc08a3-gc8054.c" \
	"$KSRC/drivers/media/i2c/gc08a3.c"
echo "installed: gc08a3-gc8054.c (GRBG, GC8054 tables)"

AUDIO=$PROJ/patches/sound/q6asm-dai-s16-4ch.patch
if patch -d "$KSRC" -p1 --dry-run < "$AUDIO" >/dev/null 2>&1; then
	patch -d "$KSRC" -p1 < "$AUDIO"
	echo "applied: $(basename "$AUDIO")"
else
	echo "skipped: $(basename "$AUDIO") (already applied or conflicting)"
fi
