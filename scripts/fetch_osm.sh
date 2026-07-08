#!/usr/bin/env bash
# Download the Geofabrik extract and cut it to the region boundary.
# In:  $GEOFABRIK (key from config/geofabrik_sources.yaml, or a full URL)
#      $WORK_DIR/region.poly (from make_boundary.py)
# Out: $WORK_DIR/region.osm.pbf
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need osmium
need curl

[ -n "$GEOFABRIK" ] || die "GEOFABRIK is not set (key from config/geofabrik_sources.yaml or URL)"
[ -f "$WORK_DIR/region.poly" ] || die "run the boundary stage first ($WORK_DIR/region.poly missing)"

if [[ "$GEOFABRIK" == http* ]]; then
    URL="$GEOFABRIK"
else
    URL="$(python3 "$REPO_DIR/scripts/yaml_get.py" get "$REPO_DIR/config/geofabrik_sources.yaml" "sources.$GEOFABRIK")"
    [[ "$URL" == http* ]] || die "unknown Geofabrik key '$GEOFABRIK' in config/geofabrik_sources.yaml"
fi

mkdir -p "$DATA_DIR"
PBF="$DATA_DIR/$(basename "$URL")"

if [ -s "$PBF" ] && [ "${REFRESH_OSM:-0}" != "1" ]; then
    log "using cached $PBF (set REFRESH_OSM=1 to re-download)"
else
    log "downloading $URL"
    curl -sSL --retry 4 --retry-delay 5 -o "$PBF.tmp" "$URL"
    mv "$PBF.tmp" "$PBF"
fi

if [ -f "$WORK_DIR/.whole-extract" ]; then
    log "whole-extract mode: linking $PBF as region.osm.pbf"
    ln -sf "$PBF" "$WORK_DIR/region.osm.pbf"
else
    log "cutting extract to region boundary"
    osmium extract --polygon "$WORK_DIR/region.poly" --strategy=smart \
        -o "$WORK_DIR/region.osm.pbf" --overwrite "$PBF"
fi

osmium fileinfo -e "$WORK_DIR/region.osm.pbf" | grep -E 'Number of|Bounding' >&2 || true
log "region extract ready: $WORK_DIR/region.osm.pbf"
