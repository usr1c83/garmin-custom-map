#!/usr/bin/env bash
# Download mkgmap and splitter from mkgmap.org.uk (pinned versions, cached).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need java
need curl
need unzip

mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

fetch_zip() {
    local name="$1" url="$2"
    if [ -d "$name" ]; then
        log "$name already present"
        return
    fi
    log "downloading $name"
    "$REPO_DIR/scripts/download.sh" "$url" "$name.zip"
    unzip -qo "$name.zip"
    rm -f "$name.zip"
}

fetch_zip "mkgmap-$MKGMAP_VERSION"   "https://www.mkgmap.org.uk/download/mkgmap-$MKGMAP_VERSION.zip"
fetch_zip "splitter-$SPLITTER_VERSION" "https://www.mkgmap.org.uk/download/splitter-$SPLITTER_VERSION.zip"

[ -f "$MKGMAP_JAR" ]   || die "mkgmap.jar missing at $MKGMAP_JAR"
[ -f "$SPLITTER_JAR" ] || die "splitter.jar missing at $SPLITTER_JAR"

log "mkgmap version: $(java -jar "$MKGMAP_JAR" --version 2>&1 | grep -v '^Picked' | head -1)"

# Optional heavyweight helpers for the base layer
if [ "$WITH_BOUNDS" = "1" ] && [ ! -d "$TOOLS_DIR/bounds" ]; then
    log "downloading bounds (~400 MB, used for the address index)"
    "$REPO_DIR/scripts/download.sh" "https://www.thkukuk.de/osm/data/bounds-latest.zip" bounds.zip
    mkdir -p bounds && unzip -qo bounds.zip -d bounds && rm bounds.zip
fi
if [ "$WITH_SEA" = "1" ] && [ ! -d "$TOOLS_DIR/sea" ]; then
    log "downloading precompiled sea (~800 MB, used for coastlines)"
    "$REPO_DIR/scripts/download.sh" "https://www.thkukuk.de/osm/data/sea-latest.zip" sea.zip
    mkdir -p sea && unzip -qo sea.zip -d sea && rm sea.zip
fi

log "toolchain OK"
