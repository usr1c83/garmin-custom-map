#!/usr/bin/env bash
# Compile one layer (base | contours | cadastre) into Garmin .img tiles + .typ.
# Usage: compile_layer.sh <layer> <input.osm[.pbf]> [more inputs...]
# Out:   $REGION_DIR/layers/<layer>/<mapid>*.img + <layer>.typ
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need java
need osmium

LAYER="${1:-}"; shift || true
[ $# -ge 1 ] || die "usage: compile_layer.sh <base|contours|cadastre> <input> [inputs...]"

case "$LAYER" in
    base)
        FID="$BASE_FID"; MAPID="$BASE_MAPID"
        STYLE="$STYLES_DIR/base-otm/style/opentopomap"
        OPTS="$REPO_DIR/config/mkgmap/base_options"
        TYP_SRC="$STYLES_DIR/base-otm/style/typ/opentopomap.txt"
        DESC="Topoosnova ${REGION_NAME}"
        ;;
    contours)
        FID="$CONTOURS_FID"; MAPID="$CONTOURS_MAPID"
        STYLE="$STYLES_DIR/contours"
        OPTS="$STYLES_DIR/contours/mkgmap-options"
        TYP_SRC="$STYLES_DIR/contours/typ.txt"
        DESC="Gorizontali ${REGION_NAME}"
        ;;
    cadastre)
        FID="$CADASTRE_FID"; MAPID="$CADASTRE_MAPID"
        STYLE="$STYLES_DIR/cadastre"
        OPTS="$STYLES_DIR/cadastre/mkgmap-options"
        TYP_SRC="$STYLES_DIR/cadastre/typ.txt"
        DESC="Kadastr ${REGION_NAME}"
        ;;
    *) die "unknown layer '$LAYER'" ;;
esac

[ -d "$STYLE" ] || die "style dir $STYLE missing (run the style stage first)"
for f in "$@"; do [ -s "$f" ] || die "input $f missing or empty"; done

OUT="$REGION_DIR/layers/$LAYER"
rm -rf "$OUT"
mkdir -p "$OUT/split"

# 1) merge inputs if several (contour tiles), then split into mkgmap tiles
INPUT="$1"
if [ $# -gt 1 ]; then
    log "[$LAYER] merging $# input files"
    osmium merge "$@" -o "$OUT/merged.osm.pbf" --overwrite
    INPUT="$OUT/merged.osm.pbf"
fi

log "[$LAYER] splitting (mapid ${MAPID}0001)"
run_java -jar "$SPLITTER_JAR" --output-dir="$OUT/split" \
    --mapid="${MAPID}0001" --max-nodes=1400000 "$INPUT" \
    > "$OUT/splitter.log" 2>&1 || { tail -20 "$OUT/splitter.log" >&2; die "splitter failed"; }

TILES=("$OUT"/split/*.osm.pbf)
[ -s "${TILES[0]}" ] || die "splitter produced no tiles"

# 2) compile TYP with this layer's family-id and the map code page
# нормализация: CodePage=1251 в колонке 0 + файл в cp1251, иначе mkgmap
# теряет/ломает кириллические подписи (детектор кодировки TYP)
python3 "$REPO_DIR/scripts/prepare_typ.py" "$TYP_SRC" "$OUT/$LAYER.txt"
(
    cd "$OUT"
    run_java -jar "$MKGMAP_JAR" --family-id="$FID" --product-id=1 \
        --code-page=1251 "$LAYER.txt" >> "$OUT/mkgmap-typ.log" 2>&1
)
TYP_FILE="$(ls "$OUT"/*.typ 2>/dev/null | head -1)"
[ -n "$TYP_FILE" ] || { tail -20 "$OUT/mkgmap-typ.log" >&2; die "TYP compilation failed"; }

# 3) compile the tiles
EXTRA=()
if [ "$LAYER" = "base" ]; then
    [ -d "$TOOLS_DIR/bounds" ] && EXTRA+=("--bounds=$TOOLS_DIR/bounds")
    [ -d "$TOOLS_DIR/sea" ]    && EXTRA+=("--precomp-sea=$TOOLS_DIR/sea")
    # DEM («карта высот»): отмывка рельефа и высота/профиль на приборе.
    # Тайлы SRTM уже скачаны стадией contours в $HGT_DIR/<ИСТОЧНИК>/
    if [ "$WITH_DEM" = "1" ]; then
        DEM_DIR="$HGT_DIR/$(echo "${HGT_SOURCE:-view3}" | tr '[:lower:]' '[:upper:]')"
        if [ -d "$DEM_DIR" ] && ls "$DEM_DIR"/*.hgt >/dev/null 2>&1; then
            EXTRA+=("--dem=$DEM_DIR")
        else
            log "[$LAYER] WITH_DEM=1, but no hgt tiles in $DEM_DIR (run the contours stage first) — DEM skipped"
        fi
    fi
fi

log "[$LAYER] mkgmap: family-id=$FID ${#TILES[@]} tile(s)"
run_java -jar "$MKGMAP_JAR" -c "$OPTS" \
    --style-file="$STYLE" \
    --family-id="$FID" \
    --family-name="$DESC" \
    --series-name="$DESC" \
    --area-name="$REGION_NAME" \
    --description="$DESC" \
    --overview-mapname="${MAPID}0000" \
    --output-dir="$OUT" \
    "${EXTRA[@]}" \
    "${TILES[@]}" \
    "$TYP_FILE" \
    > "$OUT/mkgmap.log" 2>&1 || { tail -30 "$OUT/mkgmap.log" >&2; die "mkgmap failed for $LAYER"; }

IMGS=("$OUT/${MAPID}"*.img)
[ -s "${IMGS[0]}" ] || { tail -30 "$OUT/mkgmap.log" >&2; die "no .img produced for $LAYER"; }
log "[$LAYER] done: $(ls "$OUT/${MAPID}"*.img | wc -l) img tile(s) + $(basename "$TYP_FILE")"
