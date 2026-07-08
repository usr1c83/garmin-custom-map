#!/usr/bin/env python3
"""Inspect a Garmin gmapsupp.img: list subfiles from the FAT and map products
from the MPS section. Used to verify that all layers (family-ids) made it
into the combined file. Standard library only.

Usage: inspect_img.py gmapsupp.img [--expect FID,FID,...]
"""
import argparse
import struct
import sys


def read_fat(data: bytes):
    """Yield (name, ext, size, part) for each FAT entry."""
    # header: XOR byte at 0 (mkgmap writes 0), FAT starts at 0x600? The first
    # block at 0x200.. describes the file itself; entries are 512 bytes each.
    xor = data[0]
    if xor:
        data = bytes(b ^ xor for b in data)
    entries = []
    off = 0x600
    while off + 512 <= len(data):
        flag = data[off]
        if flag != 0x01:
            break
        name = data[off + 1:off + 9].decode("ascii", "replace")
        ext = data[off + 9:off + 12].decode("ascii", "replace")
        size = struct.unpack_from("<I", data, off + 12)[0]
        part = struct.unpack_from("<H", data, off + 16)[0]
        if name.strip():
            entries.append((name, ext, size, part))
        off += 512
    return data, entries


def find_subfile(data, entries, name, ext, block_size=512):
    """Return raw bytes of a subfile by concatenating its FAT blocks."""
    blocks = []
    off = 0x600
    idx = 0
    while off + 512 <= len(data):
        if data[off] != 0x01:
            break
        n = data[off + 1:off + 9].decode("ascii", "replace")
        e = data[off + 9:off + 12].decode("ascii", "replace")
        if n == name and e == ext:
            size = struct.unpack_from("<I", data, off + 12)[0]
            seq = struct.unpack_from("<240H", data, off + 32)
            for b in seq:
                if b == 0xFFFF:
                    break
                blocks.append(b)
            if data[off + 16] == 0 and size:
                total = size
        off += 512
        idx += 1
    if not blocks:
        return b""
    # block size from header at 0x61: E1/E2 exponents
    e1, e2 = data[0x61], data[0x62]
    bs = 1 << (e1 + e2)
    out = b"".join(data[b * bs:(b + 1) * bs] for b in blocks)
    return out


def parse_mps(raw: bytes):
    """Yield MPS records ('L'|'F', fid, pid, mapnum, name).

    Record payloads start with u16 product-id, u16 family-id (mkgmap
    MapBlock/ProductBlock layout); 'L' additionally has u32 map number.
    """
    off = 0
    while off + 3 <= len(raw):
        rtype = raw[off:off + 1]
        (rlen,) = struct.unpack_from("<H", raw, off + 1)
        payload = raw[off + 3:off + 3 + rlen]
        if rtype == b"L" and rlen >= 8:
            pid, fid = struct.unpack_from("<HH", payload, 0)
            mapnum = struct.unpack_from("<I", payload, 4)[0]
            name = payload[8:].split(b"\0")[0].decode("cp1251", "replace")
            yield ("L", fid, pid, mapnum, name)
        elif rtype == b"F" and rlen >= 4:
            pid, fid = struct.unpack_from("<HH", payload, 0)
            name = payload[4:].split(b"\0")[0].decode("cp1251", "replace")
            yield ("F", fid, pid, 0, name)
        elif rlen == 0:
            break
        off += 3 + rlen


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("img")
    p.add_argument("--expect", help="comma-separated family-ids that must be present")
    a = p.parse_args()

    with open(a.img, "rb") as f:
        data = f.read()

    data, entries = read_fat(data)
    subfiles = {}
    for name, ext, size, part in entries:
        if part == 0:
            subfiles[f"{name.strip()}.{ext.strip()}"] = size

    print(f"{a.img}: {len(data) / 1e6:.1f} MB, {len(subfiles)} subfiles")
    by_ext = {}
    for full in subfiles:
        by_ext.setdefault(full.rsplit(".", 1)[1], []).append(full)
    for ext in sorted(by_ext):
        names = sorted(by_ext[ext])
        shown = ", ".join(names[:6]) + (" ..." if len(names) > 6 else "")
        print(f"  .{ext:<3} x{len(names):<3} {shown}")

    fids = set()
    mps_name = next((n for n in subfiles if n.endswith(".MPS")), None)
    if mps_name:
        name, ext = mps_name.rsplit(".", 1)
        raw = find_subfile(data, entries, f"{name:<8}"[:8], ext)
        print("map products (MPS):")
        seen = set()
        for rec in parse_mps(raw):
            rtype, fid, pid, mapnum, pname = rec
            if rtype != "L":
                continue
            fids.add(fid)
            key = (fid, pname)
            if key in seen:
                continue
            seen.add(key)
            print(f"  family {fid:5} pid {pid}  {pname!r}")
    else:
        print("no MPS subfile found (single-product img?)")

    if a.expect:
        want = {int(x) for x in a.expect.split(",")}
        missing = want - fids
        if missing:
            sys.exit(f"MISSING family-ids in {a.img}: {sorted(missing)} (found {sorted(fids)})")
        print(f"all expected family-ids present: {sorted(want)}")


if __name__ == "__main__":
    main()
