#!/bin/bash
# Produce the DBY-W09 DTB used by the boot bundle:
#   - panel rotation 90 (portrait 1600x2560 panel -> landscape for GNOME)
#   - SYH62758 backlight node at i2c 0x2e (this tablet's backlight IC)
#
# Usage: scripts/patch-dtb.sh INPUT.dtb OUTPUT.dtb
set -euo pipefail
PROJ=$(cd "$(dirname "$0")/.." && pwd)
IN=${1:?input dtb}
OUT=${2:?output dtb}
DTC=${DTC:-$(command -v dtc || true)}
[ -n "$DTC" ] || DTC=$PROJ/tools/dtc/usr/bin/dtc
[ -x "$DTC" ] || DTC=/Data/Xilinx/Vitis/2022.2/bin/dtc
[ -x "$DTC" ] || { echo "dtc not found; set DTC=/path/to/dtc" >&2; exit 1; }
export DTC
TMP=$(mktemp -d /tmp/dby-dtb.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

"$DTC" -I dtb -O dts -o "$TMP/in.dts" "$IN" 2>/dev/null
python3 - "$TMP/in.dts" "$TMP/rot.dts" <<'PY'
import sys
src, dst = sys.argv[1:3]
text = open(src, encoding="utf-8").read()
needle = 'compatible = "huawei,dby-w09-panel";'
i = text.find(needle)
if i < 0:
    raise SystemExit("panel node not found")
end = text.find("\n", i)
block = text[i:end + 400]
if "rotation =" not in block:
    text = text[:end + 1] + "\t\t\t\t\trotation = <0x5a>;\n" + text[end + 1:]
open(dst, "w", encoding="utf-8").write(text)
PY
"$DTC" -I dts -O dtb -o "$TMP/rot.dtb" "$TMP/rot.dts" 2>/dev/null

python3 "$PROJ/overrides/backlight/add-backlight.py" "$TMP/rot.dtb" "$OUT"

# Verify the two properties survived the round trip.
"$DTC" -I dtb -O dts -o "$TMP/check.dts" "$OUT" 2>/dev/null
grep -q 'compatible = "syh,syh62758"' "$TMP/check.dts" || { echo "backlight node missing" >&2; exit 1; }
grep -q 'rotation = <0x5a>' "$TMP/check.dts" || { echo "rotation missing" >&2; exit 1; }
sha256sum "$OUT"
