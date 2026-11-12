# Reproducible build guide

## Host requirements

Tested on Ubuntu 26.04.1 x86-64 with 32 CPU threads, 30 GiB RAM and 270 GiB
free. A root account is **not** required; the build uses a user namespace.

| Component | Purpose | Notes |
| --- | --- | --- |
| `debootstrap` | stage 1 of the arm64 rootfs | host package, no root needed with `--foreign` |
| `qemu-user` (`qemu-aarch64-static`) | execute arm64 packages during stage 2 | Ubuntu's `/usr/bin/qemu-aarch64` is static-pie |
| `fakeroot` + `libfakeroot` (arm64) | fake package ownership; `mke2fs -d` writes real uid/gid | extracted into the target |
| `proot` (optional) | fallback if user-namespace bind mounts are denied | not needed on this host |
| `dtc` | DTB decompile/recompile | `device-tree-compiler` |
| `e2fsprogs`, `xz-utils`, `fakeroot` | image creation/compression | host |
| kernel source + `aarch64-linux-gnu-gcc` | only for a clean kernel rebuild | see `build-kernel.sh` |

The host must allow unprivileged user namespaces. This host has
`kernel.unprivileged_userns_clone = 1`. The build mounts a private
`binfmt_misc`, a tmpfs `/dev` and a fresh `/proc` inside the user namespace; no
host-wide binfmt registration is made.

## 1. Prepare host tools

```bash
cd dby-w09-ubuntu
./scripts/prepare-host-tools.sh
```

This downloads and extracts into `tools/`:

- `debootstrap` (host package, extracted);
- `qemu-user` (host package; `usr/bin/qemu-aarch64` is the static interpreter);
- arm64 `fakeroot` and `libfakeroot` (from the Ubuntu ports pool);
- optional `qemu-system-arm` plus its shared libraries for the QEMU smoke test.

If a pinned version is no longer in the pool, override it:

```bash
FAKEROOT_VERSION=1.37.2-1 ./scripts/prepare-host-tools.sh
```

## 2. Fetch the upstream device projects

```bash
./scripts/fetch-upstream.sh
```

Clones (shallow) into `upstream/`:

- `svesnav/linux-dby-w09` — kernel, DTB, boot bundle tools;
- `svesnav/kubuntu-dby-w09` — hardware services and the installer image contract;
- `svesnav/dby-w09-installer` — Android installer/partition logic;
- `armbian/build` — Armbian audit only.

## 3. Provide a kernel bundle

The image build consumes a blob-free boot bundle and its modules:

```text
../recovery/current-linux-boot/           # Image.gz, DTB, dtbo.img,
                                           # ramdisk-payload.img, cmdline.txt
../recovery/current-modules-7.0.14-dby-w09.tar.gz
```

`build-rootfs.sh` accepts different paths:

```bash
--bundle  DIR
--modules TARBALL
```

For a clean kernel rebuild from source, see `scripts/build-kernel.sh` and the
upstream `README.md`; the output is a `linux-boot-<release>.tar` plus modules.
The image build never downloads a kernel or firmware from Huawei.

## 4. Build the rootfs

```bash
./scripts/build-rootfs.sh --from-scratch \
    --bundle  ../recovery/current-linux-boot \
    --modules ../recovery/current-modules-7.0.14-dby-w09.tar.gz
```

Stages (all are also individually runnable; see `--help`):

1. **debootstrap stage 1** — `resolute` arm64 minbase, no execution.
2. **stage 2** — through `proot` + `qemu-aarch64-static`. debootstrap's
   second stage runs dpkg on base packages whose maintainer scripts chown to
   unmapped system groups; proot intercepts those syscalls. A plain chroot is
   used only for the later package configuration, where fakeroot handles it.
3. **apt sources** — Resolute, updates, backports, security; no snaps.
4. **GNOME package set** — `configs/packages.list`.
5. **fakeroot package install** — `FAKEROOTDONTTRYCHOWN=1`, so maintainer
   scripts that `chown`/`chgrp` succeed against the fake root.
6. **build helpers** — binderfs-add, sensord, volkeys, tfa9874,
   touchscreen gesture filter; build
   `hexagonrpc` with the Huawei SLPI patches.
7. **stage hardware** — `scripts/stage-hardware.sh` (no KDE).
8. **finalize** — hostname, fstab, GDM Wayland, logind, locales, depmod.
9. **enable services** — GDM, NetworkManager, BlueZ, SSH, timesyncd, MatePad.

The script is resumable. Re-running without `--from-scratch` keeps
`build/rootfs` and only repeats the requested stages.

## 5. Build the image

```bash
./scripts/make-image.sh
```

It performs:

1. removes build-only files (`qemu-aarch64-static`, fakeroot state, apt cache);
2. records `*.packages`;
3. generates an ownership manifest from the cached `.deb` metadata,
   `dpkg-statoverride` and the fakeroot state;
4. applies `chown`/`chmod` under fakeroot and runs
   `mke2fs -d` in the same process, so the ext4 inodes get the intended
   ownership;
5. `e2fsck`, shrink, add 2 GiB free, `e2fsck`;
6. prints `debugfs` stat for sudo and the D-Bus launcher;
7. writes `*.img.xz`, `.sha256`, `.size`.

The ext4 feature set is deliberately `^orphan_file,^metadata_csum_seed` so the
HarmonyOS 4.19 kernel can mount the image while the installer copies the
device files in. Label: `LINUX70ROOT`.

## 6. Verify without a tablet

```bash
./scripts/test-qemu.sh
```

Uses the DBY kernel (which has `virtio_blk`, PL011, GICv3 and PCI built in) in
QEMU `-M virt` and boots the image to `multi-user.target`. It expects a login
prompt and no `FAILED` unit. GDM cannot be tested with this kernel because it
has no `virtio-gpu`; that part is device-only.

Expected result (recorded for the 2026-11-11 image):

```text
Welcome to Ubuntu 26.04.1 LTS!
...
[ OK ] Reached target Multi-User System.
Ubuntu 26.04.1 LTS matepad ttyAMA0
matepad login:
```

## 7. DTB patch

If you start from a stock `linux-dby-w09` bundle rather than the local recovery
bundle, apply the two local hardware adjustments:

```bash
./scripts/patch-dtb.sh input.dtb output.dtb
# then replace sm8250-huawei-dby-w09.dtb and regenerate SHA256SUMS
```

The patch adds:

- `rotation = <90>` to `panel@0` (landscape for GNOME);
- `backlight@2e` (`syh,syh62758`) for this tablet's backlight IC.

## 8. If the build host forbids unprivileged mounts

The fallback is `proot`:

```bash
PROOT_NO_SECCOMP=1 tools/proot/usr/bin/proot -q tools/qemu/root/usr/bin/qemu-aarch64 \
    -0 -r build/rootfs -b /dev -b /proc -b /sys /bin/bash
```

`scripts/rootfs-chroot.sh` uses the rootless chroot path on this host; proot
5.4.0 was used for the first inspection and is kept only as an emergency path.
