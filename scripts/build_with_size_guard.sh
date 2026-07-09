#!/usr/bin/env bash
# Build a region and keep every release file under the GitHub per-asset
# limit (2 GiB). If the single gmapsupp.img is too big, the map is re-joined
# into several standalone parts, each below the limit (see join_gmapsupp.sh).
# Map quality (contour step, DEM) is never reduced.
#
# Usage: same as run_all.sh (used by CI instead of calling run_all.sh).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAX_IMG_MB="${MAX_IMG_MB:-1950}"   # чуть ниже лимита GitHub в 2 GiB

# absorb --config here so that the re-join call below keeps the same env
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --config) # shellcheck disable=SC1090
                  set -a; source "$2"; set +a; shift 2 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

export REGION_NAME="${REGION_NAME:-region}"

"$HERE/run_all.sh" ${ARGS[@]+"${ARGS[@]}"}

OUT_REGION="${OUT_DIR:-$HERE/out}/$REGION_NAME"
IMG="$OUT_REGION/${REGION_NAME}_gmapsupp.img"
[ -s "$IMG" ] || { echo "size-guard: $IMG not found" >&2; exit 1; }

SIZE_MB=$(( $(stat -c%s "$IMG") / 1024 / 1024 ))
if [ "$SIZE_MB" -le "$MAX_IMG_MB" ]; then
    echo "size-guard: ${SIZE_MB} MiB <= ${MAX_IMG_MB} MiB — OK (single file)"
    exit 0
fi

# Слишком большой файл: НЕ упрощаем карту, а режем на части — каждая
# часть остаётся полноценным gmapsupp и вместе они дают полную карту.
echo "size-guard: ${SIZE_MB} MiB > ${MAX_IMG_MB} MiB — re-joining into parts"
export MAX_PART_MB="$MAX_IMG_MB"
"$HERE/run_all.sh" --stages join

PARTS=("$OUT_REGION/${REGION_NAME}_gmapsupp".part*.img)
[ -s "${PARTS[0]}" ] || { echo "size-guard: splitting produced no parts" >&2; exit 2; }

FAIL=0
for p in "${PARTS[@]}"; do
    MB=$(( $(stat -c%s "$p") / 1024 / 1024 ))
    echo "size-guard: $(basename "$p") = ${MB} MiB"
    [ "$MB" -le "$MAX_IMG_MB" ] || { echo "size-guard: $(basename "$p") is over the limit!" >&2; FAIL=1; }
done
[ "$FAIL" = "0" ] || exit 2
echo "size-guard: ${#PARTS[@]} part(s), all within ${MAX_IMG_MB} MiB — OK"
