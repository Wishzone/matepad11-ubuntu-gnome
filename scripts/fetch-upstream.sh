#!/bin/bash
# Fetch the upstream projects at the commits pinned in upstream.lock.
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
U=$PROJ/upstream
LOCK=$PROJ/upstream.lock
mkdir -p "$U"

[ -f "$LOCK" ] || { echo "missing $LOCK" >&2; exit 1; }

while read -r name url commit _; do
	case "$name" in ''|'#'*) continue ;; esac
	if [ -d "$U/$name/.git" ]; then
		git -C "$U/$name" fetch --depth 1 origin "$commit"
	else
		git clone --no-checkout "$url" "$U/$name"
		git -C "$U/$name" fetch --depth 1 origin "$commit"
	fi
	git -C "$U/$name" -c advice.detachedHead=false checkout --detach "$commit"
	echo "$name: $(git -C "$U/$name" log -1 --format='%h %ad %s' --date=short)"
done < "$LOCK"

# Armbian is audited only; it is not part of the DBY boot chain.  The clone is
# large, so failures are non-fatal (the audit notes live in docs/).
if [ ! -d "$U/build/.git" ]; then
	git clone --depth 1 --filter=blob:none \
		https://github.com/armbian/build.git "$U/build" || \
		echo "warning: Armbian clone failed; docs/ARCHITECTURE.md still documents the audit" >&2
fi

"$PROJ/scripts/apply-patches.sh"
