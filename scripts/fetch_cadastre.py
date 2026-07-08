#!/usr/bin/env python3
"""Download cadastral parcel boundaries for the region from the Rosreestr
public cadastral map (ПКК), or take a pre-exported GeoJSON as a fallback.

Since 2024 the ПКК lives on the НСПД portal (https://nspd.gov.ru); the old
pkk.rosreestr.ru/arcgis endpoints are gone. Land parcels ("Земельные участки
из ЕГРН") are layer 36048 served by an OGC-ish endpoint:

    https://nspd.gov.ru/api/aeggis/v3/36048/wfs   (WFS 2.0 GetFeature)
    https://nspd.gov.ru/api/geoportal/v2/search/geoportal?thematicSearchId=1&query=<кад.номер>

CAVEATS (read before debugging):
  * nspd.gov.ru is geo-blocked outside Russia and uses Russian Trusted Root
    CA certificates. From GitHub Actions or most VPS the connection is simply
    reset — this is not a bug in this script. Use --from-geojson there.
  * The portal is not a documented public API; layer ids and paths move.
    If requests fail from a Russian IP, open https://nspd.gov.ru/map, enable
    the "Земельные участки" layer, and check DevTools -> Network for the
    current layer id / URL, then pass --base-url/--layer accordingly.

Fallback: export parcels from QGIS (NGQ Rosreestr Tools plugin) or any other
tool to GeoJSON and pass --from-geojson file.geojson.

Standard library only. Output: GeoJSON FeatureCollection (EPSG:4326).
"""
import argparse
import json
import ssl
import sys
import time
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) garmin-custom-map/1.0"


def log(*a):
    print("[cadastre]", *a, file=sys.stderr)


def make_opener(insecure: bool):
    ctx = ssl.create_default_context()
    if insecure:
        # nspd.gov.ru presents certificates from the Russian Trusted Root CA
        # which is absent from standard CA bundles.
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


def http_get_json(url: str, ctx, retries: int, delay: float):
    last = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": UA,
                "Accept": "application/json",
                "Referer": "https://nspd.gov.ru/map",
            })
            with urllib.request.urlopen(req, timeout=90, context=ctx) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            last = e
            wait = delay * attempt
            log(f"attempt {attempt}/{retries} failed: {e}; sleeping {wait:.0f}s")
            time.sleep(wait)
    raise RuntimeError(f"request failed after {retries} attempts: {last}")


def bbox_of_boundary(path: str):
    with open(path, encoding="utf-8") as f:
        gj = json.load(f)
    geom = gj["geometry"] if gj.get("type") == "Feature" else gj
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    xs, ys = [], []
    for poly in polys:
        for lon, lat in poly[0]:
            xs.append(lon)
            ys.append(lat)
    return (min(xs), min(ys), max(xs), max(ys)), geom


def point_in_geom(lon: float, lat: float, geom: dict) -> bool:
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    for poly in polys:
        inside = False
        outer = poly[0]
        j = len(outer) - 1
        for i in range(len(outer)):
            xi, yi = outer[i]
            xj, yj = outer[j]
            if (yi > lat) != (yj > lat) and \
               lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        if inside:
            return True
    return False


def centroid(geom: dict):
    t = geom.get("type")
    if t == "Point":
        return geom["coordinates"]
    if t in ("Polygon", "MultiPolygon"):
        ring = geom["coordinates"][0] if t == "Polygon" else geom["coordinates"][0][0]
    elif t in ("LineString", "MultiLineString"):
        ring = geom["coordinates"] if t == "LineString" else geom["coordinates"][0]
    else:
        return None
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def fetch_wfs(args, bbox, ctx):
    """Paged WFS 2.0 GetFeature sweep over the bbox."""
    feats = []
    start = 0
    while True:
        params = urllib.parse.urlencode({
            "SERVICE": "WFS",
            "REQUEST": "GetFeature",
            "VERSION": "2.0.0",
            "TYPENAMES": args.layer,
            "OUTPUTFORMAT": "application/json",
            "SRSNAME": "urn:ogc:def:crs:EPSG::4326",
            # WFS axis order for EPSG:4326 is lat,lon
            "BBOX": f"{bbox[1]},{bbox[0]},{bbox[3]},{bbox[2]},urn:ogc:def:crs:EPSG::4326",
            "COUNT": args.page_size,
            "STARTINDEX": start,
        })
        url = f"{args.base_url}/api/aeggis/v3/{args.layer}/wfs?{params}"
        log(f"WFS page startindex={start}")
        data = http_get_json(url, ctx, args.retries, args.delay)
        page = data.get("features", [])
        feats.extend(page)
        log(f"  got {len(page)} features (total {len(feats)})")
        if len(page) < args.page_size:
            break
        start += args.page_size
        time.sleep(args.delay)
    return feats


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--boundary", required=True, help="boundary.geojson from make_boundary.py")
    p.add_argument("--out", required=True, help="output GeoJSON path")
    p.add_argument("--from-geojson", help="fallback: use this pre-exported GeoJSON instead of ПКК")
    p.add_argument("--base-url", default="https://nspd.gov.ru")
    p.add_argument("--layer", default="36048", help="NSPD layer id for Земельные участки")
    p.add_argument("--page-size", type=int, default=1000)
    p.add_argument("--retries", type=int, default=5)
    p.add_argument("--delay", type=float, default=3.0, help="base pause between requests, s")
    p.add_argument("--insecure", action="store_true",
                   help="skip TLS verification (Russian Trusted Root CA)")
    p.add_argument("--no-clip", action="store_true",
                   help="keep parcels outside the boundary polygon")
    args = p.parse_args()

    bbox, boundary_geom = bbox_of_boundary(args.boundary)

    if args.from_geojson:
        log(f"using fallback GeoJSON {args.from_geojson}")
        with open(args.from_geojson, encoding="utf-8") as f:
            gj = json.load(f)
        feats = gj["features"] if gj.get("type") == "FeatureCollection" else [gj]
    else:
        ctx = make_opener(args.insecure)
        log(f"downloading parcels from {args.base_url} layer {args.layer}, bbox {bbox}")
        try:
            feats = fetch_wfs(args, bbox, ctx)
        except RuntimeError as e:
            log(f"FAILED: {e}")
            log("If you are outside Russia this is expected (geo-blocking).")
            log("Export parcels with QGIS + NGQ Rosreestr Tools and re-run with --from-geojson.")
            sys.exit(3)

    if not args.no_clip:
        kept = []
        for f in feats:
            c = centroid(f.get("geometry") or {})
            if c and point_in_geom(c[0], c[1], boundary_geom):
                kept.append(f)
        log(f"clipped to boundary: {len(kept)}/{len(feats)} parcels kept")
        feats = kept

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"type": "FeatureCollection", "features": feats}, f, ensure_ascii=False)
    log(f"wrote {len(feats)} parcels to {args.out}")


if __name__ == "__main__":
    main()
