#!/usr/bin/env bash
# Fetch the official OpenTopoMap Garmin style (der-stefan/OpenTopoMap, garmin/)
# into styles/base-otm/. The style is not stored in this repository.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need git

DEST="$STYLES_DIR/base-otm"
OTM_REPO="${OTM_REPO:-https://github.com/der-stefan/OpenTopoMap.git}"

if [ -d "$DEST/style/opentopomap" ]; then
    log "OpenTopoMap style already fetched at $DEST"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "cloning OpenTopoMap (sparse: garmin/)"
git clone --depth 1 --filter=blob:none --sparse "$OTM_REPO" "$TMP/otm" >/dev/null 2>&1
git -C "$TMP/otm" sparse-checkout set garmin >/dev/null 2>&1

mkdir -p "$DEST"
cp -r "$TMP/otm/garmin/style" "$DEST/style"
cp "$TMP/otm/garmin/opentopomap_options" "$DEST/"
cp "$TMP/otm/garmin/contours_options" "$DEST/"

# русские подписи типов объектов (building -> здание и т.п.)
python3 "$(dirname "${BASH_SOURCE[0]}")/russify_typ.py" "$DEST/style/typ/opentopomap.txt"

log "OpenTopoMap style fetched into $DEST"
