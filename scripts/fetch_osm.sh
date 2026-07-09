#!/usr/bin/env bash
# Download the Geofabrik extract and cut it to the region boundary.
# In:  $GEOFABRIK (key from config/geofabrik_sources.yaml, or a full URL)
#      $WORK_DIR/region.poly (from make_boundary.py)
# Out: $WORK_DIR/region.osm.pbf
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need osmium
need curl

[ -n "$GEOFABRIK" ] || die "GEOFABRIK is not set (key from config/geofabrik_sources.yaml or URL)"
[ -f "$WORK_DIR/region.poly" ] || die "run the boundary stage first ($WORK_DIR/region.poly missing)"

if [[ "$GEOFABRIK" == http* ]]; then
    URL="$GEOFABRIK"
else
    URL="$(python3 "$REPO_DIR/scripts/yaml_get.py" get "$REPO_DIR/config/geofabrik_sources.yaml" "sources.$GEOFABRIK")"
    [[ "$URL" == http* ]] || die "unknown Geofabrik key '$GEOFABRIK' in config/geofabrik_sources.yaml"
fi

mkdir -p "$DATA_DIR"
PBF="$DATA_DIR/$(basename "$URL")"

# Geofabrik периодически отдаёт ошибки/битые файлы (окно обновления
# экстрактов, троттлинг параллельных скачиваний) — каждый скачанный файл
# проверяется osmium'ом, при браке повтор с паузой.
# -F pbf обязателен: без него osmium определяет формат по расширению и
# на временном имени *.tmp всегда падает (браковал валидные скачивания)
pbf_valid() { osmium fileinfo -F pbf "$1" >/dev/null 2>&1; }

if [ -s "$PBF" ] && [ "${REFRESH_OSM:-0}" != "1" ] && pbf_valid "$PBF"; then
    log "using cached $PBF (set REFRESH_OSM=1 to re-download)"
else
    rm -f "$PBF"
    for attempt in 1 2 3 4; do
        log "downloading $URL (attempt $attempt/4)"
        if "$REPO_DIR/scripts/download.sh" "$URL" "$PBF.tmp" && pbf_valid "$PBF.tmp"; then
            mv "$PBF.tmp" "$PBF"
            break
        fi
        # битый файл выбрасываем вместе с control-файлом докачки aria2
        rm -f "$PBF.tmp" "$PBF.tmp.aria2"
        [ "$attempt" -lt 4 ] || die "Geofabrik download failed or corrupt after 4 attempts: $URL"
        log "downloaded file is invalid; retrying in $((attempt * 60))s"
        sleep $((attempt * 60))
    done
fi

if [ -f "$WORK_DIR/.whole-extract" ]; then
    log "whole-extract mode: linking $PBF as region.osm.pbf"
    ln -sf "$PBF" "$WORK_DIR/region.osm.pbf"
else
    log "cutting extract to region boundary"
    osmium extract --polygon "$WORK_DIR/region.poly" --strategy=smart \
        -o "$WORK_DIR/region.osm.pbf" --overwrite "$PBF"
fi

osmium fileinfo -e "$WORK_DIR/region.osm.pbf" | grep -E 'Number of|Bounding' >&2 || true
log "region extract ready: $WORK_DIR/region.osm.pbf"
