#!/usr/bin/env python3
"""Create an ownership/mode manifest for the rootfs from the cached .debs.

dpkg was run as fake root (no host root), so chown to system groups could not
be written to the host filesystem. The .deb metadata still has the intended
owner, group and mode. This manifest is applied under fakeroot immediately
before mkfs.ext4, which writes the real uid/gid into the image.

Usage: gen-ownership.py ROOT CACHE OUT.tsv
"""
import os
import re
import stat
import subprocess
import sys

ROOT, CACHE, OUT = sys.argv[1:4]

LINE = re.compile(r"^(\S+)\s+(\S+)\s+\d+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+(.*)$")


def load_ids(path, field):
    ids = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split(":")
            if len(parts) < 3:
                continue
            try:
                ids[parts[0]] = int(parts[2])
            except ValueError:
                pass
    return ids


users = load_ids(os.path.join(ROOT, "etc/passwd"), 2)
groups = load_ids(os.path.join(ROOT, "etc/group"), 2)

entries = {}
for name in sorted(os.listdir(CACHE)):
    if not name.endswith(".deb"):
        continue
    path = os.path.join(CACHE, name)
    try:
        out = subprocess.check_output(
            ["dpkg-deb", "-c", path], text=True, errors="replace", stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError:
        print(f"skip unreadable {name}", file=sys.stderr)
        continue
    for line in out.splitlines():
        m = LINE.match(line)
        if not m:
            continue
        mode, owner, rest = m.groups()
        if " -> " in rest:
            rest = rest.split(" -> ", 1)[0]
        rel = rest[2:] if rest.startswith("./") else rest
        if not rel.startswith("usr/") and not rel.startswith("etc/") and not rel.startswith("var/") \
           and not rel.startswith("opt/") and not rel.startswith("lib/") and not rel.startswith("bin/") \
           and not rel.startswith("sbin/") and not rel.startswith("boot/") and not rel.startswith("run/"):
            continue
        full = os.path.join(ROOT, rel)
        if not os.path.lexists(full):
            continue
        if "/" in owner:
            uname, gname = owner.split("/", 1)
        else:
            uname = gname = owner
        try:
            uid = int(uname)
        except ValueError:
            uid = users.get(uname, 0)
        try:
            gid = int(gname)
        except ValueError:
            gid = groups.get(gname, 0)
        # Convert the symbolic dpkg mode to an octal mode.
        perm = 0
        if mode[0] == "d":
            perm |= 0o040000
        elif mode[0] == "l":
            perm |= 0o120000
        for i, ch in enumerate(mode[1:10]):
            if ch in "rwx":
                perm |= 1 << (8 - i)
            elif ch == "s":
                perm |= 1 << (8 - i)
                if i == 2:
                    perm |= 0o4000
                elif i == 5:
                    perm |= 0o2000
            elif ch == "t":
                perm |= 1 << (8 - i)
                perm |= 0o1000
        entries[rel] = (perm & 0o7777, uid, gid, mode[0])

# The packages' postinst scripts set setuid/setgid bits and dpkg-statoverride
# records. The actual mode on disk is authoritative; the .deb mode is not.
for rel, (mode, uid, gid, typ) in list(entries.items()):
    full = os.path.join(ROOT, rel)
    try:
        actual = stat.S_IMODE(os.lstat(full).st_mode)
    except OSError:
        continue
    entries[rel] = (actual, uid, gid, typ)

# fakeroot recorded the chown/chgrp/chmod calls made by the maintainer
# scripts. Its state is keyed by (device, inode); map those inodes back to the
# paths in the rootfs. This is what preserves, e.g., root:_ssh on ssh-agent
# and root:messagebus on the D-Bus launcher.
fake = {}
state_file = os.path.join(ROOT, "var/lib/matepad-fakeroot.state")
if os.path.exists(state_file):
    for line in open(state_file, encoding="utf-8", errors="replace"):
        kv = dict(part.split("=", 1) for part in line.strip().split(",") if "=" in part)
        try:
            fake[(int(kv["dev"]), int(kv["ino"]))] = (
                int(kv["mode"]) & 0o7777, int(kv["uid"]), int(kv["gid"]))
        except (KeyError, ValueError):
            pass
    for dirpath, dirnames, filenames in os.walk(ROOT):
        for name in dirnames + filenames:
            full = os.path.join(dirpath, name)
            try:
                st = os.lstat(full)
            except OSError:
                continue
            got = fake.get((st.st_dev, st.st_ino))
            if got is None:
                continue
            rel = os.path.relpath(full, ROOT)
            mode, uid, gid = got
            typ = "d" if stat.S_ISDIR(st.st_mode) else "l" if stat.S_ISLNK(st.st_mode) else "-"
            entries[rel] = (mode, uid, gid, typ)

# dpkg-statoverride: path -> (uid, gid, mode)
overrides = {}
so = os.path.join(ROOT, "var/lib/dpkg/statoverride")
if os.path.exists(so):
    for line in open(so, encoding="utf-8", errors="replace"):
        parts = line.split()
        if len(parts) != 4:
            continue
        uname, gname, mode, path = parts
        try:
            uid = int(uname)
        except ValueError:
            uid = users.get(uname, 0)
        try:
            gid = int(gname)
        except ValueError:
            gid = groups.get(gname, 0)
        overrides[path.lstrip("/")] = (int(mode, 8) & 0o7777, uid, gid)

# Files created by maintainer scripts, not shipped in a .deb.
shadow_gid = groups.get("shadow", 42)
utmp_gid = groups.get("utmp", 43)
adm_gid = groups.get("adm", 4)
journal_gid = groups.get("systemd-journal", 999)
fixed = {
    "etc/shadow": (0o640, 0, shadow_gid),
    "etc/shadow-": (0o640, 0, shadow_gid),
    "etc/gshadow": (0o640, 0, shadow_gid),
    "etc/gshadow-": (0o640, 0, shadow_gid),
    "etc/sudoers": (0o440, 0, 0),
    "etc/sudoers.d": (0o750, 0, 0),
    "var/log/apt": (0o750, 0, adm_gid),
    "var/log/apt/history.log": (0o640, 0, adm_gid),
    "var/log/apt/term.log": (0o640, 0, adm_gid),
    "var/log/apt/eipp.log.xz": (0o640, 0, adm_gid),
    "var/log/journal": (0o2755, 0, journal_gid),
    "var/log/wtmp": (0o664, 0, utmp_gid),
    "var/log/btmp": (0o660, 0, utmp_gid),
    "var/log/lastlog": (0o664, 0, utmp_gid),
    "run/utmp": (0o664, 0, utmp_gid),
    "usr/bin/ssh-agent": (0o2755, 0, groups.get("_ssh", 102)),
    "usr/lib/polkit-1/polkit-agent-helper-1": (0o4755, 0, 0),
    "usr/lib/openssh/ssh-keysign": (0o4755, 0, 0),
    "usr/local/share/fonts": (0o2775, 0, groups.get("staff", 50)),
    "usr/local/lib/python3.14": (0o755, 0, groups.get("staff", 50)),
    "var/lib/update-notifier/package-data-downloads/partial": (0o700, users.get("_apt", 42), 0),
}
for rel, (mode, uid, gid) in fixed.items():
    if os.path.lexists(os.path.join(ROOT, rel)):
        entries[rel] = (mode, uid, gid, "d" if os.path.isdir(os.path.join(ROOT, rel)) else "-")

for rel, (mode, uid, gid) in overrides.items():
    if os.path.lexists(os.path.join(ROOT, rel)):
        entries[rel] = (mode, uid, gid, "-")

with open(OUT, "w", encoding="utf-8") as f:
    for rel, (mode, uid, gid, typ) in sorted(entries.items()):
        f.write(f"{mode:04o}\t{uid}\t{gid}\t{typ}\t{rel}\n")
print(f"{len(entries)} entries -> {OUT}")
