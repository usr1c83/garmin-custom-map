#!/usr/bin/env python3
"""Tiny YAML subset reader (stdlib only) for this repo's config files.

Supports: nested mappings by 2-space indentation, `- ` list items (scalars or
inline single-key start of a mapping), scalar values, `#` comments, quoted
strings. That is all our configs use — this is not a general YAML parser.

Usage:
  yaml_get.py get  FILE dotted.key          -> prints scalar
  yaml_get.py json FILE [dotted.key]        -> prints JSON
"""
import json
import re
import sys


def parse_scalar(s: str):
    s = s.strip()
    if s.startswith(("'", '"')) and s.endswith(s[0]) and len(s) >= 2:
        return s[1:-1]
    if s.lower() in ("true", "yes", "on"):
        return True
    if s.lower() in ("false", "no", "off"):
        return False
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if re.fullmatch(r"-?\d+\.\d*", s):
        return float(s)
    return s


def strip_comment(line: str) -> str:
    out, quote = [], None
    for ch in line:
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#":
            break
        out.append(ch)
    return "".join(out).rstrip()


def parse_block(lines, i, indent):
    """Parse lines starting at i with exactly `indent` spaces. Returns (obj, next_i)."""
    obj = None
    while i < len(lines):
        raw = strip_comment(lines[i])
        if not raw.strip():
            i += 1
            continue
        cur = len(raw) - len(raw.lstrip(" "))
        if cur < indent:
            break
        if cur > indent:
            raise SystemExit(f"yaml_get: unexpected indent at line {i + 1}: {raw!r}")
        text = raw.strip()
        if text.startswith("- "):
            if obj is None:
                obj = []
            if not isinstance(obj, list):
                raise SystemExit(f"yaml_get: mixed list/map at line {i + 1}")
            item_text = text[2:]
            if re.match(r"^[\w.-]+:(\s|$)", item_text):
                # list of mappings: "- key: value" plus following deeper lines
                key, _, rest = item_text.partition(":")
                item = {}
                if rest.strip():
                    item[key] = parse_scalar(rest)
                    i += 1
                else:
                    sub, i = parse_block(lines, i + 1, indent + 4)
                    item[key] = sub
                # keys of the same item continue at indent+2
                more, i = parse_block(lines, i, indent + 2)
                if more:
                    if not isinstance(more, dict):
                        raise SystemExit(f"yaml_get: bad list item near line {i}")
                    item.update(more)
                obj.append(item)
            else:
                obj.append(parse_scalar(item_text))
                i += 1
        else:
            if obj is None:
                obj = {}
            if not isinstance(obj, dict):
                break
            m = re.match(r"^([^:]+):(.*)$", text)
            if not m:
                raise SystemExit(f"yaml_get: cannot parse line {i + 1}: {raw!r}")
            key, rest = m.group(1).strip(), m.group(2).strip()
            if rest:
                obj[key] = parse_scalar(rest)
                i += 1
            else:
                sub, i = parse_block(lines, i + 1, indent + 2)
                obj[key] = sub if sub is not None else {}
    return obj, i


def load(path: str):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    obj, _ = parse_block(lines, 0, 0)
    return obj


def dig(obj, dotted: str):
    for part in dotted.split("."):
        if isinstance(obj, list):
            obj = obj[int(part)]
        else:
            obj = obj[part]
    return obj


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    obj = load(path)
    if len(sys.argv) > 3:
        obj = dig(obj, sys.argv[3])
    if cmd == "get":
        print(obj)
    elif cmd == "json":
        print(json.dumps(obj, ensure_ascii=False))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
