#!/usr/bin/env python3
"""Resolve the build region into an osmosis .poly file (+ bbox + GeoJSON).

Exactly one source must be given:
  --name  "Черняховский муниципальный округ"   real admin boundary via Nominatim
  --bbox  "21.6,54.5,22.1,54.75"               west,south,east,north
  --geojson drawn.geojson                      polygon drawn in webgui/index.html
  --poly  file-or-URL                          existing osmosis .poly (e.g. Geofabrik's)

Outputs (into --out-dir):
  region.poly     for `osmium extract --polygon` and pyhgtmap --polygon
  region.bbox     "west,south,east,north" one-liner
  boundary.geojson the resolved geometry, for the cadastre stage

Standard library only.
"""
import argparse
import json
import sys
import time
import urllib.parse
import urllib.request

NOMINATIM = "https://nominatim.openstreetmap.org/search"
UA = "garmin-custom-map/1.0 (github.com/usr1c83/garmin-custom-map)"


def http_json(url: str, retries: int = 4):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            last = e
            wait = 2 ** (attempt + 1)
            print(f"nominatim attempt {attempt + 1} failed: {e}; retry in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise SystemExit(f"Nominatim request failed after {retries} tries: {last}")


def geocode(name: str) -> dict:
    q = urllib.parse.urlencode({
        "q": name,
        "format": "jsonv2",
        "limit": 5,
        "polygon_geojson": 1,
    })
    results = http_json(f"{NOMINATIM}?{q}")
    if not results:
        raise SystemExit(f"Nominatim returned no results for {name!r}")
    # Prefer a real polygon (administrative boundary) over a point/bbox hit.
    for r in results:
        if r.get("geojson", {}).get("type") in ("Polygon", "MultiPolygon"):
            print(f"resolved {name!r} -> {r.get('display_name')} "
                  f"(osm {r.get('osm_type')}/{r.get('osm_id')})", file=sys.stderr)
            return r["geojson"]
    r = results[0]
    print(f"warning: no polygon for {name!r}, falling back to bbox of "
          f"{r.get('display_name')}", file=sys.stderr)
    s, n, w, e = (float(x) for x in r["boundingbox"])
    return bbox_polygon(w, s, e, n)


def bbox_polygon(w: float, s: float, e: float, n: float) -> dict:
    return {"type": "Polygon",
            "coordinates": [[[w, s], [e, s], [e, n], [w, n], [w, s]]]}


def geometry_from_geojson_file(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        gj = json.load(f)
    if gj.get("type") == "FeatureCollection":
        geoms = [f["geometry"] for f in gj["features"]
                 if f.get("geometry", {}).get("type") in ("Polygon", "MultiPolygon")]
        if not geoms:
            raise SystemExit(f"{path}: no Polygon/MultiPolygon features")
        if len(geoms) == 1:
            return geoms[0]
        polys = []
        for g in geoms:
            polys += g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        return {"type": "MultiPolygon", "coordinates": polys}
    if gj.get("type") == "Feature":
        return gj["geometry"]
    if gj.get("type") in ("Polygon", "MultiPolygon"):
        return gj
    raise SystemExit(f"{path}: unsupported GeoJSON type {gj.get('type')}")


def geometry_from_poly(source: str) -> dict:
    if source.startswith(("http://", "https://")):
        req = urllib.request.Request(source, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=60) as r:
            text = r.read().decode()
    else:
        with open(source, encoding="utf-8") as f:
            text = f.read()
    polys, ring, hole = [], [], False
    for line in text.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        if line == "END":
            if ring:
                if ring[0] != ring[-1]:
                    ring.append(ring[0])
                if hole and polys:
                    polys[-1].append(ring)
                else:
                    polys.append([ring])
                ring = []
            continue
        parts = line.split()
        if len(parts) == 2:
            ring.append([float(parts[0]), float(parts[1])])
        else:  # ring header like "1" or "!2" (! marks a hole)
            hole = line.startswith("!")
    if not polys:
        raise SystemExit(f"no rings parsed from poly {source}")
    if len(polys) == 1:
        return {"type": "Polygon", "coordinates": polys[0]}
    return {"type": "MultiPolygon", "coordinates": polys}


def polygons(geom: dict):
    if geom["type"] == "Polygon":
        return [geom["coordinates"]]
    return geom["coordinates"]


def write_poly(geom: dict, path: str, name: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(name + "\n")
        i = 0
        for poly in polygons(geom):
            for ring_no, ring in enumerate(poly):
                i += 1
                f.write(("!%d\n" if ring_no else "%d\n") % i)
                for lon, lat in ring:
                    f.write(f"   {lon:.7f}   {lat:.7f}\n")
                f.write("END\n")
        f.write("END\n")


def bbox_of(geom: dict):
    xs, ys = [], []
    for poly in polygons(geom):
        for lon, lat in poly[0]:
            xs.append(lon)
            ys.append(lat)
    return min(xs), min(ys), max(xs), max(ys)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--name")
    src.add_argument("--bbox")
    src.add_argument("--geojson")
    src.add_argument("--poly")
    p.add_argument("--region", default="region", help="region slug for the .poly header")
    p.add_argument("--out-dir", required=True)
    a = p.parse_args()

    if a.name:
        geom = geocode(a.name)
    elif a.bbox:
        w, s, e, n = (float(x) for x in a.bbox.split(","))
        geom = bbox_polygon(w, s, e, n)
    elif a.poly:
        geom = geometry_from_poly(a.poly)
    else:
        geom = geometry_from_geojson_file(a.geojson)

    import os
    os.makedirs(a.out_dir, exist_ok=True)
    write_poly(geom, os.path.join(a.out_dir, "region.poly"), a.region)
    w, s, e, n = bbox_of(geom)
    with open(os.path.join(a.out_dir, "region.bbox"), "w") as f:
        f.write(f"{w:.6f},{s:.6f},{e:.6f},{n:.6f}\n")
    with open(os.path.join(a.out_dir, "boundary.geojson"), "w", encoding="utf-8") as f:
        json.dump({"type": "Feature", "properties": {"name": a.region},
                   "geometry": geom}, f, ensure_ascii=False)
    print(f"boundary ready: bbox={w:.4f},{s:.4f},{e:.4f},{n:.4f}", file=sys.stderr)


if __name__ == "__main__":
    main()
