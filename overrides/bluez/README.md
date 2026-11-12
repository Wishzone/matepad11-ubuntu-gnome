# BlueZ 5.85 + MatePad HOG patch (Ubuntu 26.04)

The HUAWEI MatePad Keyboard (`12d1:10b2`, HOG) answers the read of its Input
Report CCC with "Read Not Permitted".  BlueZ's `hog-lib.c` treats that as a
fatal error and never enables notifications, so the keyboard connects at the
link level but no `uhid`/input device is created.

The patch `hog-ccc-read-error.patch` makes the CCC write happen anyway and
completes the request with status 0.

## Rebuild on the tablet

```bash
mkdir -p /tmp/bluez-build && cd /tmp/bluez-build
apt-get source bluez                 # 5.85-4ubuntu0.4 on 26.04
cd bluez-5.85
patch -p1 < overrides/bluez/hog-ccc-read-error.patch
sudo apt-get build-dep -y bluez
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -uc -us -j$(nproc)
sudo dpkg -i ../bluez_5.85-4ubuntu0.4_arm64.deb
sudo systemctl restart bluetooth
bluetoothctl power on
bluetoothctl connect <keyboard-bd-addr>
```

Also set `AutoEnable=true` under `[Policy]` in `/etc/bluetooth/main.conf`
(the Ubuntu 26 upgrade left the adapter powered off at boot).

Verify:

```bash
bluetoothctl info <keyboard-bd-addr> | grep -E 'Paired|Bonded|Connected'
ls /dev/input/by-id/ | grep -i HUAWEI
dmesg | grep -i 'HUAWEI MatePad Keyboard'
```

The same patch was previously carried in the 24.04 MatePad package
`bluez 5.72-0ubuntu5.8+matepad1`.
