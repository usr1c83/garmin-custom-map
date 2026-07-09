#!/usr/bin/env bash
# Shared environment for all pipeline scripts. Source, do not execute.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

TOOLS_DIR="${TOOLS_DIR:-$REPO_DIR/tools}"
DATA_DIR="${DATA_DIR:-$REPO_DIR/data}"
OUT_DIR="${OUT_DIR:-$REPO_DIR/out}"
HGT_DIR="${HGT_DIR:-$REPO_DIR/hgt}"
STYLES_DIR="$REPO_DIR/styles"

# Pinned tool versions (see https://www.mkgmap.org.uk/download/)
MKGMAP_VERSION="${MKGMAP_VERSION:-r4924}"
SPLITTER_VERSION="${SPLITTER_VERSION:-r654}"
MKGMAP_JAR="${MKGMAP_JAR:-$TOOLS_DIR/mkgmap-$MKGMAP_VERSION/mkgmap.jar}"
SPLITTER_JAR="${SPLITTER_JAR:-$TOOLS_DIR/splitter-$SPLITTER_VERSION/splitter.jar}"

JAVA_XMX="${JAVA_XMX:-4g}"

# Region parameters. Either set directly in the environment or via a config
# file: run_all.sh --config config/examples/test-chernyakhovsk.env
REGION_NAME="${REGION_NAME:-region}"
REGION_QUERY="${REGION_QUERY:-}"        # Nominatim query, e.g. "Черняховский район"
BBOX="${BBOX:-}"                        # west,south,east,north (decimal degrees)
BOUNDARY_GEOJSON="${BOUNDARY_GEOJSON:-}" # GeoJSON polygon from webgui/index.html
GEOFABRIK="${GEOFABRIK:-}"              # key from config/geofabrik_sources.yaml or a full URL
CONTOUR_STEP="${CONTOUR_STEP:-10}"      # minor contour interval, meters
INCLUDE_CADASTRE="${INCLUDE_CADASTRE:-0}"
CADASTRE_GEOJSON="${CADASTRE_GEOJSON:-}" # fallback: pre-exported parcels GeoJSON
WITH_SEA="${WITH_SEA:-0}"               # download precomp-sea (~800 MB, needed for coastal maps)
WITH_BOUNDS="${WITH_BOUNDS:-0}"         # download bounds (~400 MB, needed for address search)
WITH_DEM="${WITH_DEM:-1}"               # embed DEM into the base layer (hillshading +
                                        # elevation profile on device; uses the same
                                        # SRTM tiles downloaded for the contours)

# Layer identity. Each layer gets its own family-id so the device lists it
# as a separate map product that can be toggled independently.
BASE_FID="${BASE_FID:-3543}"
CONTOURS_FID="${CONTOURS_FID:-3544}"
CADASTRE_FID="${CADASTRE_FID:-3545}"
# 8-digit tile name prefixes (first 4 digits, splitter appends 4 more)
BASE_MAPID="${BASE_MAPID:-3543}"
CONTOURS_MAPID="${CONTOURS_MAPID:-3544}"
CADASTRE_MAPID="${CADASTRE_MAPID:-3545}"

REGION_DIR="$OUT_DIR/$REGION_NAME"
WORK_DIR="$REGION_DIR/work"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found. Install it or use the Docker image (see README)."; }

run_java() { java "-Xmx$JAVA_XMX" "$@"; }
