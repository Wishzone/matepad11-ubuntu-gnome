#!/bin/bash
# Build linux-msm/hexagonrpc with the Huawei SLPI patches from kubuntu-dby-w09.
set -euo pipefail
S=/tmp/hexagonrpc
K=/tmp/matepad-src
cd "$S"
rm -rf build
python3 "$K/sensors/hexagonrpcd-odm.py" hexagonrpcd
python3 "$K/sensors/hexagonrpcd-sns-registry.py" hexagonrpcd "$K/sensors/sns_registry.c"
meson setup build --prefix=/usr/local --buildtype=release
ninja -C build
DESTDIR=/ ninja -C build install
ldconfig
/usr/local/bin/hexagonrpcd --help 2>&1 | head -3 || true
