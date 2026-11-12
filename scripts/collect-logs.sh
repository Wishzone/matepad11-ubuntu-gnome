#!/bin/bash
# Host-side helper: fetch the log bundle produced by matepad-collect-logs.
#
#   scripts/collect-logs.sh --ssh user@matepad.local
#   scripts/collect-logs.sh --adb          # HarmonyOS only, not the Linux boot
#
# The Linux boot exposes a USB serial console and (if enabled) SSH. The normal
# path is SSH; adb only works while HarmonyOS is booted.
set -euo pipefail
MODE=${1:---help}
case "$MODE" in
--ssh)
	HOST=${2:?user@host}
	OUT=${3:-logs}
	mkdir -p "$OUT"
	ssh "$HOST" 'sudo /usr/local/bin/matepad-collect-logs' | tee "$OUT/remote.txt"
	REMOTE=$(ssh "$HOST" 'ls -t /tmp/matepad-logs-*.tar.gz | head -1')
	scp "$HOST:$REMOTE" "$OUT/"
	echo "saved $OUT/$(basename "$REMOTE")"
	;;
--adb)
	A=${ADB:-$(cd "$(dirname "$0")/.." && pwd)/../tools/platform-tools-linux-official/platform-tools/adb}
	mkdir -p logs
	"$A" shell 'getprop | grep -E "ro.product|ro.build.version|ro.board.platform"' | tee logs/harmonyos-props.txt
	"$A" shell 'uname -a; cat /proc/cmdline' | tee logs/harmonyos-kernel.txt
	"$A" shell 'ls -l /dev/block/by-name' | tee logs/harmonyos-partitions.txt
	echo "adb is HarmonyOS only; boot Linux and use --ssh for the GNOME image"
	;;
*)
	sed -n '2,12p' "$0"
	;;
esac
