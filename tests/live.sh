#!/usr/bin/env bash
# Asks the real wooordhunt.ru the same questions tests/run.sh asks the saved pages, and
# checks the shape of the answer rather than its wording — the site is free to reword a
# gloss, but not to stop having transcriptions. Run it when a lookup looks wrong, or let
# the weekly workflow run it for you
#
# This is the one script here that needs the network. tests/run.sh never does

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODI="${ROFI_WOOORDHUNT:-$(dirname "$HERE")/rofi-wooordhunt.sh}"

fails=0

# Arguments: $1 = what the case proves, $2 = ERE the output must contain, rest = query
expect() {
  local what="$1" pattern="$2" out
  shift 2
  out=$(ROFI_RETV=1 "$MODI" "$@" | tr '\000\037' '@|')
  if grep -qE "$pattern" <<<"$out"; then
    printf '  ✓ %s\n' "$what"
  else
    printf '  ✗ %s — no line matching /%s/ for "%s"\n' "$what" "$pattern" "$*"
    sed 's/^/      /' <<<"$out"
    fails=$((fails + 1))
  fi
}

echo "live wooordhunt.ru"
expect "EN word: transcription in the header" '@message\|🇺🇸: \|' house
expect "EN word: translations as entries" '^дом@info\|дом$' house
expect "EN homograph: a transcription per part of speech" '@message\|.*\(.*\).*,.*\(.*\)' transfer
# A page is only found at all if the space became an underscore, and only a found page
# carries a transcription — so the header is the assertion about the slug
expect "EN phrase: the space became an underscore" '@message\|🇺🇸: \|' give up
expect "RU word: sections with transcriptions" '^risk \|[^|]+\|.*@info\|risk$' риск
expect "RU word: the explanation wrapped below" '^   .*@info\|.*\|nonselectable\|true$' риск
expect "RU phrase: a Latin translation" '^[A-Za-z].*@info\|' эй там
expect "a miss says so" '@message\|Nothing found' zzzqqqxxnope

if ((fails)); then
  printf '\n%d failed — the site markup moved, re-record tests/fixtures\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
