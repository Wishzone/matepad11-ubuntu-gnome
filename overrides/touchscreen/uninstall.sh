#!/bin/sh
set -e
systemctl disable --now matepad-touch-rightclick.service 2>/dev/null || true
rm -f /etc/systemd/system/matepad-touch-rightclick.service
rm -f /etc/matepad-touch-rightclick.conf
rm -f /usr/local/sbin/matepad-touch-rightclick
systemctl daemon-reload
echo removed
