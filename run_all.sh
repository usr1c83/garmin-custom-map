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
    # Источники кадастра перебираются по порядку, каждый шаг ограничен по
    # времени — сборка не может зависнуть на этом этапе:
    #   1) CADASTRE_GEOJSON — явно указанный файл;
    #   2) cadastre/<region>.geojson — выгрузка, закоммиченная в репо;
    #   3) <region>.geojson(.gz) из релиза-хранилища (тег cadastre-data);
    #   4) прямая выгрузка с НСПД (через CADASTRE_PROXY; без прокси —
    #      только вне CI, портал геоблокирован за рубежом);
    #   5) ничего не вышло — слой пропускается, сборка продолжается.
    if [ -z "$CADASTRE_GEOJSON" ] && [ -s "$HERE/cadastre/$REGION_NAME.geojson" ]; then
        CADASTRE_GEOJSON="$HERE/cadastre/$REGION_NAME.geojson"
        log "cadastre source 2/4: committed export $CADASTRE_GEOJSON"
    fi
    if [ -z "$CADASTRE_GEOJSON" ]; then
        # хранилище выгрузок: ассеты релиза cadastre-data этого же репо
        # (или любой сервер — переопределяется CADASTRE_DATA_BASE)
        DATA_BASE="${CADASTRE_DATA_BASE:-}"
        if [ -z "$DATA_BASE" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
            DATA_BASE="https://github.com/$GITHUB_REPOSITORY/releases/download/cadastre-data"
        fi
        if [ -n "$DATA_BASE" ]; then
            for ext in geojson.gz geojson; do
                URL="$DATA_BASE/$REGION_NAME.$ext"
                log "cadastre source 3/4: trying $URL"
                if "$HERE/scripts/download.sh" "$URL" "$WORK_DIR/cadastre_remote.$ext" 2>/dev/null; then
                    [ "$ext" = "geojson.gz" ] && gunzip -f "$WORK_DIR/cadastre_remote.geojson.gz"
                    CADASTRE_GEOJSON="$WORK_DIR/cadastre_remote.geojson"
                    log "cadastre source 3/4: downloaded $(du -h "$CADASTRE_GEOJSON" | cut -f1)"
                    break
                fi
            done
        fi
    fi
    if [ -z "$CADASTRE_GEOJSON" ] && [ -z "${CADASTRE_PROXY:-}" ] && [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        # источник 4 недоступен из CI без прокси (геоблокировка НСПД):
        # пропускаем сразу, не сжигая минуты на таймаутах
        log "cadastre: skipped — no export (repo/release) and no CADASTRE_PROXY secret"
        rm -f "$WORK_DIR/cadastre.osm"
        INCLUDE_CADASTRE=0
    fi
fi
if has_stage cadastre && [ "$INCLUDE_CADASTRE" = "1" ]; then
    if [ -z "$CADASTRE_GEOJSON" ] && [ -z "${CADASTRE_PROXY:-}" ]; then
        log "cadastre: no export and no proxy; trying NSPD directly (works from RU IPs)"
    fi
    CAD_ARGS=(--boundary "$WORK_DIR/boundary.geojson" --out "$WORK_DIR/cadastre.geojson")
    [ -n "$CADASTRE_GEOJSON" ] && CAD_ARGS+=(--from-geojson "$CADASTRE_GEOJSON")
    [ -n "${CADASTRE_PROXY:-}" ] && CAD_ARGS+=(--proxy "$CADASTRE_PROXY")
    [ "${CADASTRE_INSECURE:-1}" = "1" ] && [ -z "$CADASTRE_GEOJSON" ] && CAD_ARGS+=(--insecure)
    # ПКК/НСПД геоблокирована вне РФ: недоступность кадастра не должна
    # валить сборку — карта соберётся из base+contours
    if python3 "$HERE/scripts/fetch_cadastre.py" "${CAD_ARGS[@]}"; then
        python3 "$HERE/scripts/cadastre_to_osm.py" --in "$WORK_DIR/cadastre.geojson" \
            --out "$WORK_DIR/cadastre.osm"
    else
        log "WARNING: cadastre data unavailable — building WITHOUT the cadastre layer"
        rm -f "$WORK_DIR/cadastre.osm"
    fi
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
