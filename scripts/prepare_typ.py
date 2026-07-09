#!/usr/bin/env python3
"""Normalize a TYP text source for compilation with Cyrillic labels.

mkgmap's TYP charset probe only honours a `CodePage=` line that starts at
column 0; otherwise it guesses UTF-8. To make Cyrillic strings survive
deterministically we rewrite the source to CodePage=1251 at column 0 and
re-encode the file itself in cp1251. String lines that cannot be encoded
in cp1251 (e.g. German umlauts in OpenTopoMap's 0x02 slot) are dropped.

Usage: prepare_typ.py in.txt out.txt
"""
import re
import sys


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    raw = open(src, "rb").read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("cp1251")

    out_lines = []
    dropped = 0
    for line in text.splitlines():
        if re.match(r"^\s*CodePage\s*=", line):
            out_lines.append("CodePage=1251")
            continue
        try:
            line.encode("cp1251")
        except UnicodeEncodeError:
            if re.match(r"^\s*String", line):
                dropped += 1
                continue
            line = line.encode("cp1251", "replace").decode("cp1251")
        out_lines.append(line)

    with open(dst, "wb") as f:
        f.write("\n".join(out_lines).encode("cp1251") + b"\n")
    print(f"[prepare_typ] {src} -> {dst} (cp1251, dropped {dropped} non-cp1251 string(s))")


if __name__ == "__main__":
    main()
