#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "Run with sudo: $0" >&2
	exit 1
fi

ROOT=$(cd "$(dirname "$0")" && pwd)
DAEMON=${DAEMON:-/usr/local/sbin/matepad-touch-rightclick}
CONFIG=${CONFIG:-/etc/matepad-touch-rightclick.conf}
TEST_BIN=$(mktemp /tmp/matepad-touch-test.XXXXXX)
trap 'rm -f "$TEST_BIN"' EXIT

gcc -O2 -Wall -Wextra -Werror "$ROOT/touch_test.c" -o "$TEST_BIN"

run_case() {
	local label=$1
	shift
	local injector_log="/tmp/matepad-inject-$label.log"
	local daemon_log="/tmp/matepad-gesture-$label.log"
	local node=""
	local n
	local injector_pid
	local daemon_pid

	"$TEST_BIN" --single-tap --long-press --scroll "$@" >"$injector_log" 2>&1 &
	injector_pid=$!
	for n in $(seq 1 80); do
		node=$(sed -n 's/^TEST_NODE=//p' "$injector_log" | head -n 1)
		[[ -n $node ]] && break
		sleep 0.1
	done
	if [[ -z $node ]]; then
		cat "$injector_log" >&2
		kill "$injector_pid" 2>/dev/null || true
		return 1
	fi

	"$DAEMON" --dry-run --debug --device "$node" --config "$CONFIG" \
		>"$daemon_log" 2>&1 &
	daemon_pid=$!
	if [[ " $* " == *" --long-press "* ]]; then
		for n in $(seq 1 120); do
			grep -q '^LONG_PRESS_RELEASE$' "$injector_log" && break
			sleep 0.05
		done
		if ! grep -q '^LONG_PRESS_RELEASE$' "$injector_log"; then
			cat "$injector_log" "$daemon_log" >&2
			kill "$injector_pid" "$daemon_pid" 2>/dev/null || true
			return 1
		fi
		if grep -q '(long press)' "$daemon_log"; then
			echo "$label: long-press right click fired before the touchscreen lifted" >&2
			cat "$daemon_log" >&2
			kill "$injector_pid" "$daemon_pid" 2>/dev/null || true
			return 1
		fi
	fi
	wait "$injector_pid"
	sleep 0.3
	kill -TERM "$daemon_pid" 2>/dev/null || true
	wait "$daemon_pid" 2>/dev/null || true

	local taps presses scrolls
	taps=$(grep -c 'two-finger tap)' "$daemon_log" || true)
	presses=$(grep -c '(long press)' "$daemon_log" || true)
	scrolls=$(grep -c '^scroll ' "$daemon_log" || true)
	local pointer_down pointer_up
	pointer_down=$(grep -c '^pointer-left down at ' "$daemon_log" || true)
	pointer_up=$(grep -c '^pointer-left up at ' "$daemon_log" || true)
	[[ $taps -eq 5 && $presses -eq 1 && $scrolls -ge 2 &&
	   $pointer_down -ge 2 && $pointer_up -ge 2 ]] || {
		cat "$daemon_log" >&2
		echo "$label: expected taps, single-pointer tap/hold, long press and scrolling; got $taps taps, $presses presses, $scrolls scroll steps, pointer events $pointer_down/$pointer_up" >&2
		return 1
	}
	echo "$label: 5 taps, 1 long press and $scrolls scroll steps passed"
}

run_case type-a
run_case type-b --type-b

run_rotation_case() {
	local rotation_file config injector_log daemon_log node
	local injector_pid daemon_pid rotation_pid n
	rotation_file=$(mktemp /tmp/matepad-rotation.XXXXXX)
	config=$(mktemp /tmp/matepad-gesture-config.XXXXXX)
	injector_log=/tmp/matepad-inject-rotation.log
	daemon_log=/tmp/matepad-gesture-rotation.log
	sed "s#^ROTATION_FILE=.*#ROTATION_FILE=$rotation_file#" "$CONFIG" >"$config"
	echo 3 >"$rotation_file"
	"$TEST_BIN" --type-b --scroll >"$injector_log" 2>&1 &
	injector_pid=$!
	for n in $(seq 1 80); do
		node=$(sed -n 's/^TEST_NODE=//p' "$injector_log" | head -n 1)
		[[ -n $node ]] && break
		sleep 0.1
	done
	if [[ -z $node ]]; then
		cat "$injector_log" >&2
		kill "$injector_pid" 2>/dev/null || true
		rm -f "$rotation_file" "$config"
		return 1
	fi
	"$DAEMON" --dry-run --device "$node" --config "$config" \
		>"$daemon_log" 2>&1 &
	daemon_pid=$!
	(sleep 4; echo 0 >"$rotation_file"; sleep 2; echo 3 >"$rotation_file") &
	rotation_pid=$!
	wait "$injector_pid"
	wait "$rotation_pid"
	kill -TERM "$daemon_pid" 2>/dev/null || true
	wait "$daemon_pid" 2>/dev/null || true
	grep -q 'orientation changed: 0 degrees, logical screen=800x1280' "$daemon_log"
	grep -q 'orientation changed: 270 degrees, logical screen=1280x800' "$daemon_log"
	rm -f "$rotation_file" "$config"
	echo "rotation-file: portrait/landscape mapping passed"
}

run_rotation_case
