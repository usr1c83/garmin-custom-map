#!/usr/bin/env bash
# Build a region and keep the img under the GitHub Releases per-file limit
# (2 GiB). If the result is bigger than MAX_IMG_MB, increase the contour
# step by 5 m and rebuild contours+compile+join, up to MAX_TRIES times.
#
# Usage: same as run_all.sh (used by CI instead of calling run_all.sh).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAX_IMG_MB="${MAX_IMG_MB:-1950}"   # чуть ниже лимита GitHub в 2 GiB
MAX_TRIES="${MAX_TRIES:-3}"

# absorb --config here so that rebuild iterations can override CONTOUR_STEP
# (run_all's own --config would re-source the file and reset the step)
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --config) # shellcheck disable=SC1090
                  set -a; source "$2"; set +a; shift 2 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

export REGION_NAME="${REGION_NAME:-region}"
export CONTOUR_STEP="${CONTOUR_STEP:-10}"

"$HERE/run_all.sh" ${ARGS[@]+"${ARGS[@]}"}

IMG="${OUT_DIR:-$HERE/out}/$REGION_NAME/${REGION_NAME}_gmapsupp.img"
[ -s "$IMG" ] || { echo "size-guard: $IMG not found" >&2; exit 1; }

for try in $(seq 1 "$MAX_TRIES"); do
    SIZE_MB=$(( $(stat -c%s "$IMG") / 1024 / 1024 ))
    if [ "$SIZE_MB" -le "$MAX_IMG_MB" ]; then
        echo "size-guard: ${SIZE_MB} MiB <= ${MAX_IMG_MB} MiB — OK"
        exit 0
    fi
    export CONTOUR_STEP=$((CONTOUR_STEP + 5))
    echo "size-guard: ${SIZE_MB} MiB > ${MAX_IMG_MB} MiB — rebuild ${try}/${MAX_TRIES} with contour step ${CONTOUR_STEP} m"
    "$HERE/run_all.sh" --stages contours,compile,join
done

SIZE_MB=$(( $(stat -c%s "$IMG") / 1024 / 1024 ))
if [ "$SIZE_MB" -le "$MAX_IMG_MB" ]; then
    echo "size-guard: ${SIZE_MB} MiB <= ${MAX_IMG_MB} MiB — OK"
    exit 0
fi
echo "size-guard: still ${SIZE_MB} MiB after ${MAX_TRIES} rebuilds (step ${CONTOUR_STEP} m)." >&2
echo "size-guard: split the region in config/release_regions.yaml or raise contour_step." >&2
exit 2
