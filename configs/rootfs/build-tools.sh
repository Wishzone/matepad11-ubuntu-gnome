#!/bin/bash
# Compile the small C hardware helpers inside the arm64 rootfs.
set -euo pipefail
umask 022
S=/tmp/matepad-src
mkdir -p /usr/local/lib/linux70-touch /usr/local/sbin /usr/local/bin
gcc -O2 -Wall -o /usr/local/lib/linux70-touch/binderfs-add "$S/touch/binderfs_add.c"
gcc -O2 -Wall -DWITH_SDBUS -o /usr/local/sbin/matepad-sensord "$S/sensors/matepad_sensord.c" -lsystemd -lm
gcc -O2 -Wall -pthread -o /usr/local/sbin/matepad-volkeys "$S/sound/volkeys/matepad_volkeys.c" -lsystemd
gcc -O2 -Wall -o /usr/local/sbin/matepad-tfa9874 "$S/sound/matepad_tfa9874.c"
gcc -O2 -Wall -Wextra -Werror -o /usr/local/sbin/matepad-touch-rightclick \
	"$S/touch/matepad-touch-rightclick.c" -lm
gcc -shared -fPIC -O2 -Wall -Wextra -Werror \
	-o /usr/local/lib/matepad-upower-sign.so "$S/upower/matepad-upower-sign.c" -ldl
ls -l /usr/local/lib/linux70-touch/binderfs-add /usr/local/sbin/matepad-sensord \
	      /usr/local/sbin/matepad-volkeys /usr/local/sbin/matepad-tfa9874 \
	      /usr/local/sbin/matepad-touch-rightclick /usr/local/lib/matepad-upower-sign.so
