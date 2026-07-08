#!/usr/bin/env bash
# Join all compiled layers into a single gmapsupp.img.
# Each layer keeps its own family-id + TYP, so the device lists three
# separate map products that can be enabled/disabled independently.
# Out: $REGION_DIR/gmapsupp.img (+ copy named <region>_gmapsupp.img)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need java

# mkgmap applies options positionally: an option affects only the input
# files listed after it. Passing --family-id before each layer's files keeps
# every layer a separate map product inside gmapsupp.img (otherwise all
# tiles are re-tagged with the default family 6324 and the device shows a
# single non-toggleable product).
INPUTS=()
EXPECT=()
add_layer() {
    local layer="$1" fid="$2" name="$3"
    local dir="$REGION_DIR/layers/$layer"
    [ -d "$dir" ] || { log "layer $layer not built, skipping"; return; }
    local files=()
    for img in "$dir"/*.img; do
        case "$(basename "$img")" in
            *0000.img|osmmap*.img|ovm_*.img) continue ;;
            *) files+=("$img") ;;
        esac
    done
    [ ${#files[@]} -gt 0 ] || { log "layer $layer has no tiles, skipping"; return; }
    local typ
    typ="$(ls "$dir"/*.typ 2>/dev/null | head -1)"
    INPUTS+=(--family-id="$fid" --product-id=1 \
             --family-name="$name" --series-name="$name" \
             "${files[@]}")
    [ -n "$typ" ] && INPUTS+=("$typ")
    EXPECT+=("$fid")
}

add_layer base     "$BASE_FID"     "OTM $REGION_NAME"
add_layer contours "$CONTOURS_FID" "Contours $REGION_NAME"
add_layer cadastre "$CADASTRE_FID" "Cadastre $REGION_NAME"

[ ${#INPUTS[@]} -gt 0 ] || die "no compiled layers found under $REGION_DIR/layers"

log "joining ${#INPUTS[@]} files into gmapsupp.img"
run_java -jar "$MKGMAP_JAR" --gmapsupp \
    --description="garmin-custom-map $REGION_NAME" \
    --output-dir="$REGION_DIR" \
    "${INPUTS[@]}" > "$REGION_DIR/join.log" 2>&1 \
    || { tail -30 "$REGION_DIR/join.log" >&2; die "gmapsupp join failed"; }

[ -s "$REGION_DIR/gmapsupp.img" ] || die "gmapsupp.img was not produced"

cp "$REGION_DIR/gmapsupp.img" "$REGION_DIR/${REGION_NAME}_gmapsupp.img"

log "verifying layer inventory inside gmapsupp.img"
python3 "$REPO_DIR/scripts/inspect_img.py" "$REGION_DIR/gmapsupp.img" \
    --expect "$(IFS=,; echo "${EXPECT[*]}")"

log "final map: $REGION_DIR/${REGION_NAME}_gmapsupp.img ($(du -h "$REGION_DIR/gmapsupp.img" | cut -f1))"
