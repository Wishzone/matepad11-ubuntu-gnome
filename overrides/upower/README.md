# UPower current-sign compatibility shim

This tablet's PM8150B GEN4 fuel gauge (and the `matepad-fg` driver) reports a
**negative** battery current while charging, matching Huawei's stock sign.
UPower 1.91 has a change that forces `state=discharging` whenever
`current_now < 0`, even when sysfs says `status=Charging`; GNOME therefore
showed a discharging battery while the charger was connected.

`matepad-upower-sign.c` is compiled into an LD_PRELOAD shim for `upowerd` only. It wraps
`g_udev_device_get_sysfs_attr_as_double_uncached()` and returns the absolute
value for the `current_now` attribute, so UPower sees the Linux-standard
positive-charging sign. The kernel and every other consumer keep the stock
sign.

Build manually (the rootfs build compiles this source automatically):

```bash
aarch64-linux-gnu-gcc -shared -fPIC -O2 \
    -o matepad-upower-sign.so matepad-upower-sign.c -ldl
```

Install:

```bash
install -m 755 matepad-upower-sign.so /usr/local/lib/
install -d /etc/systemd/system/upower.service.d
cat >/etc/systemd/system/upower.service.d/10-matepad-sign.conf <<'EOF'
[Service]
Environment=LD_PRELOAD=/usr/local/lib/matepad-upower-sign.so
EOF
systemctl daemon-reload
systemctl restart upower
```

Result after a direct charger:

```text
upower -i .../battery_battery
  state: charging
sysfs:
  status=Charging
  current_now=-1074218
```

The cleaner long-term fix is to expose positive charging current from
`matepad-fg.c`; that requires a kernel + boot-image rebuild. This shim is
small, reversible and keeps the GNOME image usable now.
