#!/bin/sh
# Build and install the MatePad right-click gesture daemon on the tablet.
set -e
cd "$(dirname "$0")"
bin=$(mktemp /tmp/matepad-touch-rightclick.XXXXXX)
trap 'rm -f "$bin"' EXIT
gcc -O2 -Wall -Wextra -Werror matepad-touch-rightclick.c -lm -o "$bin"
install -Dm755 "$bin" /usr/local/sbin/matepad-touch-rightclick
install -Dm644 matepad-touch-rightclick.conf /etc/matepad-touch-rightclick.conf
install -Dm644 matepad-touch-rightclick.service /etc/systemd/system/matepad-touch-rightclick.service
systemctl daemon-reload
systemctl enable matepad-touch-rightclick.service
systemctl restart matepad-touch-rightclick.service
sleep 1
systemctl is-active --quiet matepad-touch-rightclick.service
systemctl --no-pager --full status matepad-touch-rightclick.service | head -n 12
