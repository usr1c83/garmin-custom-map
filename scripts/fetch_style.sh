#!/usr/bin/env bash
# Fetch the official OpenTopoMap Garmin style (der-stefan/OpenTopoMap, garmin/)
# into styles/base-otm/. The style is not stored in this repository.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need git

DEST="$STYLES_DIR/base-otm"
OTM_REPO="${OTM_REPO:-https://github.com/der-stefan/OpenTopoMap.git}"

if [ -d "$DEST/style/opentopomap" ]; then
    log "OpenTopoMap style already fetched at $DEST (re-applying patches)"
else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    log "cloning OpenTopoMap (sparse: garmin/)"
    git clone --depth 1 --filter=blob:none --sparse "$OTM_REPO" "$TMP/otm" >/dev/null 2>&1
    git -C "$TMP/otm" sparse-checkout set garmin >/dev/null 2>&1

    mkdir -p "$DEST"
    cp -r "$TMP/otm/garmin/style" "$DEST/style"
    cp "$TMP/otm/garmin/opentopomap_options" "$DEST/"
    cp "$TMP/otm/garmin/contours_options" "$DEST/"
fi

# русские подписи типов объектов (building -> здание и т.п.)
python3 "$(dirname "${BASH_SOURCE[0]}")/russify_typ.py" "$DEST/style/typ/opentopomap.txt"

# видимые номера домов: OTM-стиль их не рисует. Правило вставляется перед
# секцией <finalize> (в конец главной секции правил); addr:housenumber с
# building-полигонов попадает в points через add-pois-to-areas.
if ! grep -q 'garmin-custom-map: housenumbers' "$DEST/style/opentopomap/points"; then
    python3 - "$DEST/style/opentopomap/points" <<'EOF'
import sys
path = sys.argv[1]
text = open(path).read()
rule = ("# --- garmin-custom-map: housenumbers (видимые номера домов) ---\n"
        "addr:housenumber=* { name '${addr:housenumber}' } [0x11500 resolution 24]\n\n")
text = text.replace("<finalize>", rule + "<finalize>", 1)
open(path, "w").write(text)
print("[fetch_style] housenumber rule added to points")
EOF
fi
if ! grep -q '0x11500' "$DEST/style/typ/opentopomap.txt"; then
    cat >> "$DEST/style/typ/opentopomap.txt" <<'EOF'

; garmin-custom-map: house number point (tiny dot, label shows the number)
[_point]
Type=0x11500
FontStyle=SmallFont
DayXpm="4 4 2 1"
"! c #666666"
"  c none"
"    "
" !! "
" !! "
"    "
[end]
EOF
    echo "[fetch_style] housenumber point added to TYP"
fi

log "OpenTopoMap style fetched into $DEST"
