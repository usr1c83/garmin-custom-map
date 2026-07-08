#!/usr/bin/env bash
# Запуск пайплайна в Docker без установки тулчейна на хост
# (Linux / macOS / Git Bash / WSL).
#   ./docker-run.sh --config config/examples/test-chernyakhovsk.env
#   REGION_NAME=suzdal REGION_QUERY="Суздальский район" GEOFABRIK=central-fd ./docker-run.sh
set -euo pipefail

cd "$(dirname "$0")"
IMAGE="${IMAGE:-garmin-custom-map}"

if [ "${REBUILD:-0}" = "1" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo ">> building Docker image $IMAGE"
    docker build ${DOCKER_BUILD_ARGS:-} -t "$IMAGE" .
fi

# прокидываем переменные региона (и прокси, если есть), если заданы на хосте
ENV_ARGS=()
for v in REGION_NAME REGION_QUERY BBOX BOUNDARY_GEOJSON GEOFABRIK CONTOUR_STEP \
         INCLUDE_CADASTRE CADASTRE_GEOJSON CADASTRE_INSECURE CADASTRE_PROXY WITH_SEA WITH_BOUNDS \
         JAVA_XMX HGT_SOURCE MKGMAP_VERSION SPLITTER_VERSION REFRESH_OSM \
         HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
    if [ -n "${!v:-}" ]; then ENV_ARGS+=(-e "$v=${!v}"); fi
done

TTY_ARGS=()
if [ -t 0 ]; then TTY_ARGS+=(-it); fi

# DOCKER_RUN_ARGS: дополнительные аргументы docker run (--network=host и т.п.)
# shellcheck disable=SC2086
exec docker run --rm "${TTY_ARGS[@]}" \
    -v "$(pwd):/work" \
    "${ENV_ARGS[@]}" \
    ${DOCKER_RUN_ARGS:-} \
    "$IMAGE" ./run_all.sh "$@"
