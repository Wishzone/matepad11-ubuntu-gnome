#!/bin/bash
# Rebuild the DBY kernel + modules + blob-free boot bundle from source.
# This is optional for the rootfs image (the image consumes a bundle), but it
# is the reproducible path for a new kernel release.
#
# Requirements: aarch64-linux-gnu-gcc, bc, bison, flex, libssl-dev, dtc, cpio,
# kmod, python3, and a Linux 7.0.y source tree.
#
#   SOURCE_DIR=~/linux-7.0.y OUTPUT_DIR=~/dby-kbuild \
#   MATEPAD_WORK_DIR=~/dby-work scripts/build-kernel.sh
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
U=$PROJ/upstream/linux-dby-w09
SOURCE_DIR=${SOURCE_DIR:?set SOURCE_DIR to a Linux 7.0.y tree}
OUTPUT_DIR=${OUTPUT_DIR:-$PROJ/build/kernel}
MATEPAD_WORK_DIR=${MATEPAD_WORK_DIR:-$PROJ/build/kernel-work}
mkdir -p "$OUTPUT_DIR" "$MATEPAD_WORK_DIR/build"

[ -f "$SOURCE_DIR/Makefile" ] || { echo "no kernel source at $SOURCE_DIR" >&2; exit 1; }
[ -d "$U" ] || { echo "run scripts/fetch-upstream.sh first" >&2; exit 1; }

"$PROJ/scripts/apply-kernel-patches.sh" "$SOURCE_DIR"

export SOURCE_DIR OUTPUT_DIR MATEPAD_WORK_DIR
export PATH="$PATH"

echo "== configure and build"
"$U/configure-and-build.sh"
echo "== modules"
"$U/build_modules.sh"
echo "== static busybox for the initramfs"
if [ ! -x "$MATEPAD_WORK_DIR/build/ubuntu-busybox-aarch64" ]; then
	"$U/fetch_busybox.sh" "$MATEPAD_WORK_DIR/build/ubuntu-busybox-aarch64"
fi
echo "== release bundle"
"$U/build_release.sh"

BUNDLE=$(ls -t "$MATEPAD_WORK_DIR/build/release"/linux-boot-*.tar 2>/dev/null | head -1)
[ -n "$BUNDLE" ] || { echo "no bundle produced" >&2; exit 1; }
cp "$BUNDLE" "$PROJ/build/"
echo "bundle: $BUNDLE"
echo "modules: $MATEPAD_WORK_DIR/build/linux-70-modules.tar.gz"
