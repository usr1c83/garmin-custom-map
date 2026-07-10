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
# ВАЖНО: osmium merge держит буферы ВСЕХ входов одновременно — на тысячах
# файлов (ДВ ФО: 2840 тайлов горизонталей) память 16-ГБ раннера кончается
# и VM убивает агент («The runner has received a shutdown signal», три
# воспроизведения подряд ровно на этой стадии). Поэтому сливаем партиями
# по MERGE_BATCH файлов, затем один финальный merge частей.
MERGE_BATCH="${MERGE_BATCH:-300}"
INPUT="$1"
if [ $# -gt 1 ]; then
    log "[$LAYER] merging $# input files (batch=$MERGE_BATCH)"
    if [ $# -gt "$MERGE_BATCH" ]; then
        rm -rf "$OUT/merge"; mkdir -p "$OUT/merge"
        part=0
        while [ $# -gt 0 ]; do
            batch=("${@:1:$MERGE_BATCH}")
            shift "${#batch[@]}"
            osmium merge "${batch[@]}" -o "$OUT/merge/part$part.osm.pbf" --overwrite
            part=$((part+1))
        done
        log "[$LAYER] merging $part intermediate part(s)"
        osmium merge "$OUT"/merge/part*.osm.pbf -o "$OUT/merged.osm.pbf" --overwrite
        rm -rf "$OUT/merge"
    else
        osmium merge "$@" -o "$OUT/merged.osm.pbf" --overwrite
    fi
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
            # обрезаем DEM границей региона. Критично для Дальневосточного
            # ФО: тайл сплиттера с данными по обе стороны 180-го меридиана
            # получает bbox почти на весь мир, и без обрезки его DEM-секция
            # превышает форматный лимит Garmin 256 МиБ («The DEM section of
            # the map or tile is too big»). Пустота вне полигона кодируется
            # почти бесплатно, DEM внутри региона не страдает.
            [ -s "$WORK_DIR/region.poly" ] && EXTRA+=("--dem-poly=$WORK_DIR/region.poly")
        else
            log "[$LAYER] WITH_DEM=1, but no hgt tiles in $DEM_DIR (run the contours stage first) — DEM skipped"
        fi
    fi
fi

# при падении показываем ПРИЧИНУ, а не только хвост: хвост mkgmap.log
# забивают безобидные HGTReader-предупреждения, а стектрейс
# (MapFailedException и т.п.) остаётся выше по логу
mkgmap_fail_dump() {
    {
        echo "--- exception context from mkgmap.log ---"
        grep -aB 3 -A 30 -E "Exception|SEVERE|Error executing" "$OUT/mkgmap.log" | tail -120
        echo "--- last lines of mkgmap.log ---"
        tail -10 "$OUT/mkgmap.log"
    } >&2
}

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
    > "$OUT/mkgmap.log" 2>&1 || { mkgmap_fail_dump; die "mkgmap failed for $LAYER"; }

IMGS=("$OUT/${MAPID}"*.img)
[ -s "${IMGS[0]}" ] || { mkgmap_fail_dump; die "no .img produced for $LAYER"; }
log "[$LAYER] done: $(ls "$OUT/${MAPID}"*.img | wc -l) img tile(s) + $(basename "$TYP_FILE")"
