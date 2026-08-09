#!/usr/bin/env bash
# Downloads every page tests/fixtures/routes names, so the saved set is derived from the
# routing table rather than from whatever was fetched by hand once
#
#   tests/refresh.sh              re-record tests/fixtures in place
#   tests/refresh.sh <dir>        download into <dir> instead, leaving the saved set alone
#
# The second form is what the weekly workflow uses: it runs the offline suite against the
# fresh copy, so a golden diff is the site's markup having moved

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROUTES="$HERE/fixtures/routes"
BASE="${ROFI_WOOORDHUNT_URL:-https://wooordhunt.ru}"
DEST="${1:-$HERE/fixtures}"

mkdir -p "$DEST"
[[ "$DEST" -ef "$HERE/fixtures" ]] || cp "$ROUTES" "$DEST/routes"

fails=0
while IFS=$'\t' read -r path file; do
  [[ -z "$path" || "$path" == \#* ]] && continue
  if curl -fsSL --max-time 20 "$BASE/$path" -o "$DEST/$file"; then
    printf '  ✓ %s → %s (%s bytes)\n' "$path" "$file" "$(wc -c <"$DEST/$file")"
  else
    printf '  ✗ %s — the site did not serve it\n' "$path"
    fails=$((fails + 1))
  fi
done <"$ROUTES"

if ((fails)); then
  printf '\n%d pages missing — a route that 404s is already the markup moving\n' "$fails"
  exit 1
fi
printf '\ndownloaded into %s\n' "$DEST"
