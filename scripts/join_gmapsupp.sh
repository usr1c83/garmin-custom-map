#!/usr/bin/env bash
# Join all compiled layers into gmapsupp.img.
#
# Each layer keeps its own family-id + TYP, so the device lists separate
# map products that can be enabled/disabled independently.
#
# If MAX_PART_MB is set and the tiles don't fit into one file of that size,
# the map is SPLIT into several standalone gmapsupp files
# (<region>_gmapsupp.part1.img, .part2.img, ...) — each below the limit,
# each valid on its own; together they form the complete map. Quality
# (contour step, DEM) is never degraded.
#
# Out: $REGION_DIR/<region>_gmapsupp.img            (single mode)
#      $REGION_DIR/<region>_gmapsupp.partN.img ...  (parts mode)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need java

# --- collect compiled layers: fid / product name / typ / tiles ---
LAYER_LIST=()
declare -A L_FID L_NAME L_TYP L_TILES
for spec in "base;$BASE_FID;Topoosnova" \
            "contours;$CONTOURS_FID;Gorizontali" \
            "cadastre;$CADASTRE_FID;Kadastr"; do
    IFS=';' read -r layer fid tname <<< "$spec"
    dir="$REGION_DIR/layers/$layer"
    [ -d "$dir" ] || { log "layer $layer not built, skipping"; continue; }
    tiles=()
    for img in "$dir"/*.img; do
        case "$(basename "$img")" in
            *0000.img|osmmap*.img|ovm_*.img|*_mdr.img) continue ;;
            *) tiles+=("$img") ;;
        esac
    done
    [ ${#tiles[@]} -gt 0 ] || { log "layer $layer has no tiles, skipping"; continue; }
    LAYER_LIST+=("$layer")
    L_FID[$layer]="$fid"
    L_NAME[$layer]="$tname $REGION_NAME"
    L_TYP[$layer]="$(ls "$dir"/*.typ 2>/dev/null | head -1)"
    L_TILES[$layer]="${tiles[*]}"
done
[ ${#LAYER_LIST[@]} -gt 0 ] || die "no compiled layers found under $REGION_DIR/layers"

# join one output file from the given "layer=tile tile ..." groups
join_one() {
    local out_name="$1"; shift
    local inputs=() expect=() layer
    for group in "$@"; do
        layer="${group%%=*}"
        # shellcheck disable=SC2206
        local tiles=(${group#*=})
        [ ${#tiles[@]} -gt 0 ] || continue
        inputs+=(--family-id="${L_FID[$layer]}" --product-id=1 \
                 --family-name="${L_NAME[$layer]}" --series-name="${L_NAME[$layer]}" \
                 "${tiles[@]}")
        [ -n "${L_TYP[$layer]}" ] && inputs+=("${L_TYP[$layer]}")
        expect+=("${L_FID[$layer]}")
    done
    log "joining $out_name (${#inputs[@]} args)"
    # --index кладёт в gmapsupp поисковые индексы (MDR) — без них на
    # приборе не работает поиск городов/адресов
    run_java -jar "$MKGMAP_JAR" --gmapsupp --index \
        --code-page=1251 \
        --description="garmin-custom-map $REGION_NAME" \
        --output-dir="$REGION_DIR" \
        "${inputs[@]}" > "$REGION_DIR/join-$out_name.log" 2>&1 \
        || { tail -30 "$REGION_DIR/join-$out_name.log" >&2; die "gmapsupp join failed ($out_name)"; }
    mv "$REGION_DIR/gmapsupp.img" "$REGION_DIR/$out_name"

    # mkgmap пишет MPS в latin1 — возвращаем русские названия слоёв (cp1251)
    python3 "$REPO_DIR/scripts/fix_mps_names.py" "$REGION_DIR/$out_name" \
        "Topoosnova=Топооснова" "Gorizontali=Горизонтали" "Kadastr=Кадастр"

    python3 "$REPO_DIR/scripts/inspect_img.py" "$REGION_DIR/$out_name" \
        --expect "$(IFS=,; echo "${expect[*]}")"
}

tiles_bytes() {
    local total=0 f
    for f in "$@"; do total=$((total + $(stat -c%s "$f"))); done
    echo "$total"
}

# --- single-file mode -------------------------------------------------------
ALL_TILES=()
for layer in "${LAYER_LIST[@]}"; do
    # shellcheck disable=SC2206
    ALL_TILES+=(${L_TILES[$layer]})
done
TOTAL_MB=$(( $(tiles_bytes "${ALL_TILES[@]}") / 1024 / 1024 ))

if [ -z "${MAX_PART_MB:-}" ] || [ "$TOTAL_MB" -le $(( MAX_PART_MB * 85 / 100 )) ]; then
    JOIN_GROUPS=()
    for layer in "${LAYER_LIST[@]}"; do JOIN_GROUPS+=("$layer=${L_TILES[$layer]}"); done
    rm -f "$REGION_DIR/${REGION_NAME}_gmapsupp".part*.img
    join_one "${REGION_NAME}_gmapsupp.img" "${JOIN_GROUPS[@]}"
    cp "$REGION_DIR/${REGION_NAME}_gmapsupp.img" "$REGION_DIR/gmapsupp.img"
    log "final map: $REGION_DIR/${REGION_NAME}_gmapsupp.img ($(du -h "$REGION_DIR/gmapsupp.img" | cut -f1))"
    exit 0
fi

# --- parts mode: greedy packing under the size budget -----------------------
# Бюджет считается по входным тайлам, но выход больше входа (MDR/SRT/TYP
# и служебные секции). Начинаем с 85% лимита; если какая-то часть всё же
# вылезла — пересплит с меньшим бюджетом.
log "splitting into parts: tiles total ${TOTAL_MB} MiB (MAX_PART_MB=${MAX_PART_MB})"
rm -f "$REGION_DIR/${REGION_NAME}_gmapsupp.img" "$REGION_DIR/gmapsupp.img"

declare -A PART_TILES   # layer -> tiles of the current part
PART_NO=0
PART_SIZE=0
PART_ORDER=()

flush_part() {
    [ "$PART_SIZE" -gt 0 ] || return 0
    PART_NO=$((PART_NO + 1))
    local groups=() layer
    for layer in "${PART_ORDER[@]}"; do
        groups+=("$layer=${PART_TILES[$layer]}")
    done
    join_one "${REGION_NAME}_gmapsupp.part${PART_NO}.img" "${groups[@]}"
    PART_TILES=(); PART_ORDER=(); PART_SIZE=0
}

RATIO=85
for attempt in 1 2 3 4; do
    BUDGET=$(( MAX_PART_MB * 1024 * 1024 * RATIO / 100 ))
    log "parts attempt $attempt: budget $((BUDGET / 1024 / 1024)) MiB per part"
    rm -f "$REGION_DIR/${REGION_NAME}_gmapsupp".part*.img
    PART_NO=0; PART_SIZE=0; PART_ORDER=(); PART_TILES=()

    for layer in "${LAYER_LIST[@]}"; do
        # shellcheck disable=SC2206
        tiles=(${L_TILES[$layer]})
        for tile in "${tiles[@]}"; do
            sz=$(stat -c%s "$tile")
            if [ "$PART_SIZE" -gt 0 ] && [ $((PART_SIZE + sz)) -gt "$BUDGET" ]; then
                flush_part
            fi
            if [ -z "${PART_TILES[$layer]:-}" ]; then
                PART_ORDER+=("$layer")
                PART_TILES[$layer]="$tile"
            else
                PART_TILES[$layer]="${PART_TILES[$layer]} $tile"
            fi
            PART_SIZE=$((PART_SIZE + sz))
        done
    done
    flush_part

    OVERSIZE=0
    for p in "$REGION_DIR/${REGION_NAME}_gmapsupp".part*.img; do
        MB=$(( $(stat -c%s "$p") / 1024 / 1024 ))
        if [ "$MB" -ge "$MAX_PART_MB" ]; then
            log "$(basename "$p") = ${MB} MiB >= ${MAX_PART_MB} MiB — retrying with smaller budget"
            OVERSIZE=1
        fi
    done
    [ "$OVERSIZE" = "0" ] && break
    RATIO=$(( RATIO * 3 / 4 ))
done
[ "$OVERSIZE" = "0" ] || die "cannot fit parts under ${MAX_PART_MB} MiB (a single tile is too big?)"

log "final map in $PART_NO parts: $REGION_DIR/${REGION_NAME}_gmapsupp.part{1..$PART_NO}.img"
log "(на прибор копируются ВСЕ части — вместе они образуют полную карту)"
