#!/usr/bin/env bash
# Generate contour lines from SRTM/viewfinderpanoramas with pyhgtmap
# (maintained fork of phyghtmap; same CLI).
# In:  $WORK_DIR/region.poly, $CONTOUR_STEP
# Out: $WORK_DIR/contours/*.osm.pbf
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need pyhgtmap

[ -f "$WORK_DIR/region.poly" ] || die "run the boundary stage first"

CONTOURS_DIR="$WORK_DIR/contours"
rm -rf "$CONTOURS_DIR"
mkdir -p "$CONTOURS_DIR" "$HGT_DIR"

# medium/major categories: OpenTopoMap's contours style highlights every
# 5th/10th line (e.g. step 10 -> medium 50, major 100)
MEDIUM=$((CONTOUR_STEP * 5))
MAJOR=$((CONTOUR_STEP * 10))

log "generating contours: step=${CONTOUR_STEP}m medium=${MEDIUM}m major=${MAJOR}m source=${HGT_SOURCE:-view3}"
(
    cd "$CONTOURS_DIR"
    pyhgtmap \
        --polygon="$WORK_DIR/region.poly" \
        --step="$CONTOUR_STEP" \
        --line-cat="$MAJOR,$MEDIUM" \
        --no-zero-contour \
        --source="${HGT_SOURCE:-view3}" \
        --hgtdir="$HGT_DIR" \
        --jobs="$(nproc)" \
        --simplifyContoursEpsilon=0.00005 \
        --start-node-id=20000000000 --start-way-id=20000000000 \
        --pbf \
        --output-prefix=contours
)

ls -1 "$CONTOURS_DIR"/*.osm.pbf >/dev/null 2>&1 || die "pyhgtmap produced no output"
log "contours ready: $(ls "$CONTOURS_DIR"/*.osm.pbf | wc -l) tile(s)"
