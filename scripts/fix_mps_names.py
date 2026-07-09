#!/usr/bin/env python3
"""Restore Cyrillic product names inside gmapsupp.img MPS records.

mkgmap writes MPS strings in latin1 (and JVM argv decoding depends on the
locale), so Cyrillic can't be passed through the command line reliably.
Instead the pipeline passes ASCII transliterations of the layer names to
mkgmap and this script swaps them for equal-byte-length cp1251 Russian
text directly inside the MPS subfile (record layout is untouched).

Usage: fix_mps_names.py map.img Topoosnova=Топооснова Kadastr=Кадастр ...
Every replacement pair must have equal byte length (ASCII vs cp1251).
"""
import struct
import sys


def main() -> None:
    img_path = sys.argv[1]
    pairs = []
    for arg in sys.argv[2:]:
        src, _, dst = arg.partition("=")
        src_b, dst_b = src.encode("ascii"), dst.encode("cp1251")
        if len(src_b) != len(dst_b):
            sys.exit(f"fix_mps_names: length mismatch {src!r} ({len(src_b)}) vs {dst!r} ({len(dst_b)})")
        pairs.append((src_b, dst_b))

    with open(img_path, "rb") as f:
        data = bytearray(f.read())
    if data[0] != 0:
        sys.exit("fix_mps_names: XORed img not supported")

    # locate the MPS subfile blocks via the FAT
    bs = 1 << (data[0x61] + data[0x62])
    mps_blocks = []
    off = 0x600
    while off + 512 <= len(data) and data[off] == 1:
        if data[off + 9:off + 12] == b"MPS":
            for b in struct.unpack_from("<240H", data, off + 32):
                if b == 0xFFFF:
                    break
                mps_blocks.append(b)
        off += 512
    if not mps_blocks:
        print("fix_mps_names: no MPS subfile, nothing to do")
        return

    patched = 0
    for blk in mps_blocks:
        start, end = blk * bs, (blk + 1) * bs
        chunk = bytes(data[start:end])
        fixed = chunk
        for src_b, dst_b in pairs:
            fixed = fixed.replace(src_b, dst_b)
        if fixed != chunk:
            data[start:end] = fixed
            patched += 1

    with open(img_path, "wb") as f:
        f.write(data)
    print(f"fix_mps_names: patched {patched} MPS block(s) in {img_path}")


if __name__ == "__main__":
    main()
