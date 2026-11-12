# MatePad touchscreen gesture filter

`matepad-touch-rightclick` grabs the DBY-W09 `input_mt_wrapper` device and
converts it to a virtual uinput pointer:

- one finger: left-button click and drag;
- two fingers moving together: vertical/horizontal wheel events at the fingers'
  midpoint;
- two-finger tap or stationary one-finger long press: right-click after lift;
- pinch and three-or-more-finger contacts: suppressed, so applications cannot
  treat the same two-finger scroll as native zoom.

The M-Pencil is a separate input device and remains on its normal native path.
If the service exits or is stopped, the kernel touchscreen event path resumes
when the evdev grab is released.

## Display mapping

The current GNOME landscape output is 1280×800 logical at 2× scale. The daemon
maps the raw portrait sensor axes using the current `/sys/touchscreen/rotation`
value and rebuilds its virtual pointer when orientation changes. Update
`matepad-touch-rightclick.conf` if GNOME's scale or output mode changes.

## Build and test

The rootfs build compiles the daemon from this directory and stages its systemd
unit/config. To run the synthetic parser tests on the tablet:

```bash
sudo tests/touchscreen/test-gestures.sh
```

The tests cover Type-A and Type-B reports, short taps, single-finger pointer
emulation, long-press ordering, scroll wheel generation, and orientation changes.
Physical gesture verification is tracked in `docs/DEVICE-STATUS.md`.

## Installed paths

- `/usr/local/sbin/matepad-touch-rightclick` — daemon
- `/etc/matepad-touch-rightclick.conf` — logical screen size and gesture timing
- `/etc/systemd/system/matepad-touch-rightclick.service` — boot service
