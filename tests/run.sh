#!/usr/bin/env bash
# Drives the modi against saved pages and diffs the rofi protocol it emits against
# tests/golden. Nothing here touches the network: a stub curl on PATH serves
# tests/fixtures according to tests/fixtures/routes
#
#   tests/run.sh           check against the golden files
#   tests/run.sh --update  re-record them after a deliberate change

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")
MODI="${ROFI_WOOORDHUNT:-$REPO/rofi-wooordhunt.sh}"
GOLDEN="$HERE/golden"
UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# tests/stub shadows the real curl and the clipboard, so nothing here leaves the machine
export PATH="$HERE/stub:$PATH"
export FIXTURES="$HERE/fixtures"
export COPIED="$WORK/copied"
export ROFI_WOOORDHUNT_URL="https://wooordhunt.invalid"
export ROFI_WOOORDHUNT_COPY="fake-copy"
export ROFI_WOOORDHUNT_PROMPT="🤓"

fails=0

fail() {
  printf '  ✗ %s\n' "$1"
  fails=$((fails + 1))
}

# Renders the NUL/US-separated rofi protocol readable, so a golden diff points at a
# field rather than at an unprintable byte
readable() {
  tr '\000\037' '@|'
}

# Arguments: $1 = golden name, rest = query words
check() {
  local name="$1" got want
  shift
  got=$(ROFI_RETV=1 "$MODI" "$@" | readable)
  want="$GOLDEN/$name.txt"
  if ((UPDATE)); then
    printf '%s\n' "$got" >"$want"
    printf '  ✎ %s\n' "$name"
    return
  fi
  if [[ ! -f "$want" ]]; then
    fail "$name: no golden file — run tests/run.sh --update"
    return
  fi
  if diff -u "$want" <(printf '%s\n' "$got") >"$WORK/diff"; then
    printf '  ✓ %s\n' "$name"
  else
    fail "$name"
    sed 's/^/      /' "$WORK/diff"
  fi
}

echo "parsing"
check en-word house
check en-homograph transfer
check en-phrase give up
check ru-sections риск
check ru-many-sections экзамен
check ru-light-phrase эй там
check empty
check miss zzzqqqxxnope
check timeout __timeout__
check transport-error __boom__

((UPDATE)) && exit 0

echo "locale"

# The wrapping counts characters, and a C locale makes fold and ${#s} count bytes —
# the modi has to bring its own UTF-8 rather than inherit the session's
if diff -q "$GOLDEN/ru-sections.txt" \
  <(LC_ALL=C LANG=C ROFI_RETV=1 "$MODI" риск | readable) >/dev/null; then
  echo "  ✓ layout survives LC_ALL=C"
else
  fail "LC_ALL=C: the layout follows the session locale"
  # The one thing worth knowing next: which UTF-8 locale the machine could have given it
  printf '      locales available: %s\n' "$(locale -a 2>/dev/null | grep -i utf | tr '\n' ' ')"
fi

# …and a locale name this machine does not have must not take the layout with it
if diff -q "$GOLDEN/ru-sections.txt" \
  <(ROFI_WOOORDHUNT_LOCALE=zz_ZZ.bogus ROFI_RETV=1 "$MODI" риск | readable) >/dev/null; then
  echo "  ✓ an unusable locale falls back"
else
  fail "an unusable locale: the layout went with it"
fi

echo "protocol"

# The mode names itself, so nothing has to be declared in the rofi config
if ROFI_RETV=0 "$MODI" | readable | grep -qxF '@prompt|🤓'; then
  echo "  ✓ prompt"
else
  fail "prompt: the modi does not name itself"
fi

# An entry carries its copy value in info, and picking it copies exactly that
: >"$COPIED"
ROFI_RETV=1 ROFI_INFO="дом" "$MODI" >"$WORK/out"
if [[ "$(cat "$COPIED")" == "дом" && ! -s "$WORK/out" ]]; then
  echo "  ✓ copy"
else
  fail "copy: expected the info value on the clipboard and no further output"
fi

# The "---" row a failed lookup leaves behind must stay inert when activated
: >"$COPIED"
ROFI_RETV=1 ROFI_INFO="__wooordhunt_noop__" "$MODI" >/dev/null
if [[ ! -s "$COPIED" ]]; then
  echo "  ✓ noop row copies nothing"
else
  fail "noop row: the placeholder ended up on the clipboard"
fi

# Wrapping is what keeps a long gloss inside the window; a wider window has to widen it
narrow=$(ROFI_RETV=1 ROFI_WOOORDHUNT_WRAP_WIDTH=20 "$MODI" риск | readable | grep -c '^   ')
wide=$(ROFI_RETV=1 ROFI_WOOORDHUNT_WRAP_WIDTH=200 "$MODI" риск | readable | grep -c '^   ')
if ((narrow > wide)); then
  echo "  ✓ wrap width"
else
  fail "wrap width: $narrow hint lines at 20 columns vs $wide at 200"
fi

echo "usage"
if "$MODI" --help | grep -q ROFI_WOOORDHUNT_PROMPT; then
  echo "  ✓ --help lists the settings"
else
  fail "--help: the settings are undocumented"
fi

# …but only outside rofi, where "--help" can only be a query
if ROFI_RETV=1 "$MODI" --help | readable | grep -q '@message'; then
  echo "  ✓ --help inside rofi is a query"
else
  fail "--help inside rofi: usage leaked into the mode"
fi

if ((fails)); then
  printf '\n%d failed\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
