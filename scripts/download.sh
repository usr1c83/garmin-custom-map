#!/usr/bin/env bash
# Единый надёжный загрузчик для всех скачиваний пайплайна.
#
# aria2c: несколько потоков + докачка после обрыва (-c) — переживает
# серверы, рвущие длинные соединения (Geofabrik режет ~на 60-й секунде
# при загрузке с IP GitHub-раннеров). Если aria2 не установлен —
# fallback на curl с resume.
#
# Usage: download.sh <url> <output-file>
# Env:   DOWNLOAD_CONNECTIONS (потоков на сервер, default 4)
#        DOWNLOAD_TRIES       (попыток, default 10)
set -euo pipefail

URL="$1"
OUT="$2"
CONNS="${DOWNLOAD_CONNECTIONS:-4}"
TRIES="${DOWNLOAD_TRIES:-10}"

mkdir -p "$(dirname "$OUT")"

if command -v aria2c >/dev/null 2>&1; then
    aria2c \
        --console-log-level=warn \
        --summary-interval=0 \
        --download-result=hide \
        -x "$CONNS" -s "$CONNS" -k 10M \
        -c \
        --max-tries="$TRIES" --retry-wait=20 \
        --connect-timeout=30 --timeout=90 \
        --allow-overwrite=true --auto-file-renaming=false \
        --dir "$(dirname "$OUT")" --out "$(basename "$OUT")" \
        "$URL"
else
    curl -sSfL --retry "$TRIES" --retry-delay 15 --retry-all-errors \
        -C - -o "$OUT" "$URL"
fi
