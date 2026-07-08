#!/usr/bin/env bash
# Orchestrate the full pipeline:
#   tools -> style -> boundary -> osm -> contours -> cadastre -> compile -> join
#
# Usage:
#   ./run_all.sh --config config/examples/test-chernyakhovsk.env
#   REGION_NAME=suzdal REGION_QUERY="Суздальский район" GEOFABRIK=central-fd ./run_all.sh
#   ./run_all.sh --config my.env --stages contours,compile,join   # rerun a part
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STAGES="tools,style,boundary,osm,contours,cadastre,compile,join"

while [ $# -gt 0 ]; do
    case "$1" in
        --config)  # shellcheck disable=SC1090
                   set -a; source "$2"; set +a; shift 2 ;;
        --stages)  STAGES="$2"; shift 2 ;;
        --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

source "$HERE/scripts/common.sh"

has_stage() { case ",$STAGES," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

log "=== region=$REGION_NAME stages=$STAGES ==="
mkdir -p "$WORK_DIR"

has_stage tools && "$HERE/scripts/fetch_tools.sh"
has_stage style && "$HERE/scripts/fetch_style.sh"

if has_stage boundary; then
    if [ -n "$BOUNDARY_GEOJSON" ]; then
        python3 "$HERE/scripts/make_boundary.py" --geojson "$BOUNDARY_GEOJSON" \
            --region "$REGION_NAME" --out-dir "$WORK_DIR"
    elif [ -n "$BBOX" ]; then
        python3 "$HERE/scripts/make_boundary.py" --bbox "$BBOX" \
            --region "$REGION_NAME" --out-dir "$WORK_DIR"
    elif [ -n "$REGION_QUERY" ]; then
        python3 "$HERE/scripts/make_boundary.py" --name "$REGION_QUERY" \
            --region "$REGION_NAME" --out-dir "$WORK_DIR"
    elif [ -n "$GEOFABRIK" ]; then
        # whole extract: use Geofabrik's own .poly as the boundary and skip
        # the osmium cut (fetch_osm.sh checks the marker file)
        if [[ "$GEOFABRIK" == http* ]]; then
            POLY_URL="${GEOFABRIK/-latest.osm.pbf/.poly}"
        else
            SRC_URL="$(python3 "$HERE/scripts/yaml_get.py" get "$HERE/config/geofabrik_sources.yaml" "sources.$GEOFABRIK")"
            POLY_URL="${SRC_URL/-latest.osm.pbf/.poly}"
        fi
        python3 "$HERE/scripts/make_boundary.py" --poly "$POLY_URL" \
            --region "$REGION_NAME" --out-dir "$WORK_DIR"
        touch "$WORK_DIR/.whole-extract"
    else
        die "set REGION_QUERY, BBOX or BOUNDARY_GEOJSON"
    fi
fi

has_stage osm && "$HERE/scripts/fetch_osm.sh"
has_stage contours && "$HERE/scripts/make_contours.sh"

if has_stage cadastre && [ "$INCLUDE_CADASTRE" = "1" ]; then
    CAD_ARGS=(--boundary "$WORK_DIR/boundary.geojson" --out "$WORK_DIR/cadastre.geojson")
    [ -n "$CADASTRE_GEOJSON" ] && CAD_ARGS+=(--from-geojson "$CADASTRE_GEOJSON")
    [ "${CADASTRE_INSECURE:-1}" = "1" ] && [ -z "$CADASTRE_GEOJSON" ] && CAD_ARGS+=(--insecure)
    python3 "$HERE/scripts/fetch_cadastre.py" "${CAD_ARGS[@]}"
    python3 "$HERE/scripts/cadastre_to_osm.py" --in "$WORK_DIR/cadastre.geojson" \
        --out "$WORK_DIR/cadastre.osm"
fi

if has_stage compile; then
    "$HERE/scripts/compile_layer.sh" base "$WORK_DIR/region.osm.pbf"
    "$HERE/scripts/compile_layer.sh" contours "$WORK_DIR"/contours/*.osm.pbf
    if [ "$INCLUDE_CADASTRE" = "1" ] && [ -s "$WORK_DIR/cadastre.osm" ]; then
        "$HERE/scripts/compile_layer.sh" cadastre "$WORK_DIR/cadastre.osm"
    fi
fi

has_stage join && "$HERE/scripts/join_gmapsupp.sh"

log "=== done: $REGION_DIR ==="
