#!/usr/bin/env python3
"""Convert a cadastral parcels GeoJSON into OSM XML for mkgmap.

Each parcel ring becomes a closed way tagged
    cadastre=parcel
    name=<кадастровый номер>       (picked from common ПКК/NSPD property names)
so styles/cadastre can render boundary lines labelled with the number.
Nodes shared between adjacent parcels are deduplicated by coordinate.

Standard library only.
"""
import argparse
import json
import sys
from xml.sax.saxutils import escape

# property names seen in ПКК/NSPD/QGIS exports for the cadastral number
CAD_NUM_KEYS = ("cad_num", "cad_number", "cadNum", "CAD_NUM", "cn",
                "cadastral_number", "kadastr", "options.cad_num", "label")


def cad_number(props: dict) -> str:
    for k in CAD_NUM_KEYS:
        cur, ok = props, True
        for part in k.split("."):
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                ok = False
                break
        if ok and cur not in (None, ""):
            return str(cur)
    return ""


def rings_of(geom: dict):
    t = geom.get("type")
    if t == "Polygon":
        yield from geom["coordinates"]
    elif t == "MultiPolygon":
        for poly in geom["coordinates"]:
            yield from poly
    elif t == "LineString":
        yield geom["coordinates"]
    elif t == "MultiLineString":
        yield from geom["coordinates"]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--in", dest="src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--start-id", type=int, default=30_000_000_000,
                   help="first (negative-space) OSM id; keep clear of contour ids")
    a = p.parse_args()

    with open(a.src, encoding="utf-8") as f:
        gj = json.load(f)
    feats = gj["features"] if gj.get("type") == "FeatureCollection" else [gj]

    nodes = {}          # (lon,lat) rounded -> node id
    ways = []           # (way id, [node ids], name)
    next_id = a.start_id

    for feat in feats:
        geom = feat.get("geometry")
        if not geom:
            continue
        name = cad_number(feat.get("properties") or {})
        for ring in rings_of(geom):
            ids = []
            for coord in ring:
                lon, lat = float(coord[0]), float(coord[1])
                key = (round(lon, 7), round(lat, 7))
                nid = nodes.get(key)
                if nid is None:
                    nid = next_id
                    next_id += 1
                    nodes[key] = nid
                if not ids or ids[-1] != nid:
                    ids.append(nid)
            if len(ids) < 2:
                continue
            ways.append((next_id, ids, name))
            next_id += 1

    with open(a.out, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<osm version="0.6" generator="cadastre_to_osm">\n')
        for (lon, lat), nid in nodes.items():
            f.write(f'  <node id="{nid}" lat="{lat:.7f}" lon="{lon:.7f}" version="1"/>\n')
        for wid, ids, name in ways:
            f.write(f'  <way id="{wid}" version="1">\n')
            for nid in ids:
                f.write(f'    <nd ref="{nid}"/>\n')
            f.write('    <tag k="cadastre" v="parcel"/>\n')
            if name:
                f.write(f'    <tag k="name" v="{escape(name)}"/>\n')
            f.write('  </way>\n')
        f.write('</osm>\n')

    print(f"[cadastre_to_osm] {len(feats)} parcels -> {len(ways)} ways, "
          f"{len(nodes)} nodes -> {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
