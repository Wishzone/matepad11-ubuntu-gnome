#!/bin/bash
# Apply the project's local patches to the fetched upstream kernel tree.
# Resets the touched files first, so running it twice is safe.
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
U=$PROJ/upstream/linux-dby-w09

PATCHES=(
	patches/0001-huawei-thp-lite-tabletmode-pen-rotation.patch
	patches/0002-enable-bt-rfcomm.patch
	patches/0003-huawei-thp-type-b-multitouch.patch
)

[ -d "$U/.git" ] || {
	echo "missing $U: run scripts/fetch-upstream.sh first" >&2
	exit 1
}

git -C "$U" checkout -- touch/huawei-thp-lite.c configure-and-build.sh
for p in "${PATCHES[@]}"; do
	[ -f "$PROJ/$p" ] || {
		echo "missing $p" >&2
		exit 1
	}
	git -C "$U" apply "$PROJ/$p"
	echo "applied: $(basename "$p")"
done
