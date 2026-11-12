#!/usr/bin/env python3
"""Add the SYH62758 backlight node to the DBY-W09 DTB.

The board's bl-en-regulator already holds the backlight IC's EN pin high.
Give that regulator a phandle and add a backlight@2e node that uses it as
vcc-supply.  The existing disabled rt8555 node at 0x31 is left alone.

Usage: python3 add-backlight.py <input.dtb> <output.dtb>
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

BL_EN_OLD = '''\tbl-en-regulator {
\t\tcompatible = "regulator-fixed";
\t\tregulator-name = "bl_en";
\t\tregulator-min-microvolt = <0x1b7740>;
\t\tregulator-max-microvolt = <0x1b7740>;
\t\tgpio = <0x3b 0x0a 0x00>;
\t\tenable-active-high;
\t\tregulator-always-on;
\t\tregulator-boot-on;
\t};'''

BL_EN_NEW = '''\tbl-en-regulator {
\t\tcompatible = "regulator-fixed";
\t\tregulator-name = "bl_en";
\t\tregulator-min-microvolt = <0x1b7740>;
\t\tregulator-max-microvolt = <0x1b7740>;
\t\tgpio = <0x3b 0x0a 0x00>;
\t\tenable-active-high;
\t\tregulator-always-on;
\t\tregulator-boot-on;
\t\tphandle = <0x7f4>;
\t};'''

BL_OLD = '''\t\t\t\tbacklight@31 {
\t\t\t\t\tcompatible = "richtek,rt8555";
\t\t\t\t\treg = <0x31>;
\t\t\t\t\tstatus = "disabled";
\t\t\t\t\tenable-gpios = <0x3b 0x0a 0x00>;
\t\t\t\t\tphandle = <0xfd>;
\t\t\t\t};'''

BL_NEW = '''\t\t\t\tbacklight@31 {
\t\t\t\t\tcompatible = "richtek,rt8555";
\t\t\t\t\treg = <0x31>;
\t\t\t\t\tstatus = "disabled";
\t\t\t\t\tenable-gpios = <0x3b 0x0a 0x00>;
\t\t\t\t\tphandle = <0xfd>;
\t\t\t\t};

\t\t\t\tbacklight@2e {
\t\t\t\t\tcompatible = "syh,syh62758";
\t\t\t\t\treg = <0x2e>;
\t\t\t\t\tvcc-supply = <0x7f4>;
\t\t\t\t\tstatus = "okay";
\t\t\t\t};'''


def find_dtc():
    for cand in (os.environ.get("DTC"), "dtc",
                 "/Data/Xilinx/Vitis/2022.2/bin/dtc"):
        if not cand:
            continue
        if os.path.isabs(cand):
            if os.path.exists(cand):
                return cand
        else:
            p = shutil.which(cand)
            if p:
                return p
    raise SystemExit("dtc not found; set DTC=/path/to/dtc")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    dtc = find_dtc()
    tmp = tempfile.mkdtemp(prefix="backlight-")
    dts = os.path.join(tmp, "base.dts")
    try:
        subprocess.run([dtc, "-I", "dtb", "-O", "dts", "-o", dts, src],
                       check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        text = open(dts, encoding="utf-8").read()
        if 'compatible = "syh,syh62758"' in text:
            print("input already contains syh62758")
            shutil.copy2(src, dst)
            return
        for old, label in ((BL_EN_OLD, "bl-en"), (BL_OLD, "backlight@31")):
            if text.count(old) != 1:
                raise SystemExit(f"{label} anchor count {text.count(old)} != 1")
        text = text.replace(BL_EN_OLD, BL_EN_NEW, 1)
        text = text.replace(BL_OLD, BL_NEW, 1)
        patched = os.path.join(tmp, "patched.dts")
        open(patched, "w", encoding="utf-8").write(text)
        out = os.path.join(tmp, "out.dtb")
        subprocess.run([dtc, "-I", "dts", "-O", "dtb", "-o", out, patched],
                       check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        check = subprocess.run([dtc, "-I", "dtb", "-O", "dts", "-o", "-", out],
                               check=True, capture_output=True, text=True).stdout
        for needle in ('compatible = "syh,syh62758"',
                       'vcc-supply = <0x7f4>',
                       'phandle = <0x7f4>'):
            if needle not in check:
                raise SystemExit(f"verification failed: {needle}")
        shutil.copy2(out, dst)
        print(f"wrote {dst}")
        print(f"input  sha256: {sha256(src)}")
        print(f"output sha256: {sha256(dst)}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
