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

# pyhgtmap opens sockets without a timeout; viewfinderpanoramas.org
# intermittently stalls connections, which once froze a CI job for hours.
# Force a global socket timeout and split the run into a retried download
# phase and an offline generation phase (the hgt cache persists between
# attempts, so progress accumulates).
PYHGT=(python3 -c 'import socket, sys
socket.setdefaulttimeout(90)
from pyhgtmap.main import main
sys.exit(main())')

COMMON_ARGS=(
    --polygon="$WORK_DIR/region.poly"
    --step="$CONTOUR_STEP"
    --line-cat="$MAJOR,$MEDIUM"
    --no-zero-contour
    --source="${HGT_SOURCE:-view3}"
    --hgtdir="$HGT_DIR"
)

log "downloading elevation tiles (source=${HGT_SOURCE:-view3}, retries with timeout)"
DL_OK=0
for attempt in 1 2 3 4 5; do
    if "${PYHGT[@]}" "${COMMON_ARGS[@]}" --download-only; then
        DL_OK=1
        break
    fi
    log "download attempt $attempt failed; retrying in $((attempt * 30))s"
    sleep $((attempt * 30))
done
[ "$DL_OK" = "1" ] || die "elevation download failed after 5 attempts (viewfinderpanoramas.org down?)"

# NOTE: --jobs > 1 deadlocks in pyhgtmap 4.1 (children fork with npyosmium
# writer threads and hang in add_way). Single process is reliable; override
# with PYHGT_JOBS at your own risk.
log "generating contours: step=${CONTOUR_STEP}m medium=${MEDIUM}m major=${MAJOR}m"
(
    cd "$CONTOURS_DIR"
    "${PYHGT[@]}" \
        "${COMMON_ARGS[@]}" \
        --jobs="${PYHGT_JOBS:-1}" \
        --simplifyContoursEpsilon=0.00005 \
        --start-node-id=20000000000 --start-way-id=20000000000 \
        --pbf \
        --output-prefix=contours
)

ls -1 "$CONTOURS_DIR"/*.osm.pbf >/dev/null 2>&1 || die "pyhgtmap produced no output"
log "contours ready: $(ls "$CONTOURS_DIR"/*.osm.pbf | wc -l) tile(s)"
