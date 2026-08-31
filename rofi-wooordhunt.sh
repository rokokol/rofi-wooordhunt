#!/usr/bin/env bash

# The launcher, and the only executable meant for a keybinding or a shell. It hands rofi
# the absolute path of the modi, which is why the modi itself has no business on PATH
set -euo pipefail

MODE="dictionary"
# The fallback resolves through symlinks, so a link to this script on PATH still finds
# its modi; under Nix the wrapper sets the variable and this never runs
MODI="${ROFI_WOOORDHUNT_MODI:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/wooordhunt-modi.sh}"

usage() {
  cat <<EOF
rofi-wooordhunt — a rofi dictionary translating both ways through wooordhunt.ru

  rofi-wooordhunt [word]   open the dictionary; a word given here fills the search line
  rofi -modi "x:rofi-wooordhunt"
                           it works as a mode of your own rofi too, next to whatever
                           else you keep there — run that way it steps aside and lets
                           the parser answer
  rofi-wooordhunt --modi   print where that parser lives. Not needed for the line
                           above; it is for pointing rofi straight at it, or for
                           looking at what actually runs
  rofi-wooordhunt --version
                           print the version

Type in either direction; Enter copies the highlighted entry. Environment:

  ROFI_WOOORDHUNT_PROMPT       rofi mode name (default: 🤓)
  ROFI_WOOORDHUNT_COPY         clipboard command fed on stdin (default: wl-copy)
  ROFI_WOOORDHUNT_URL          site root (default: https://wooordhunt.ru)
  ROFI_WOOORDHUNT_TIMEOUT      per-request timeout in seconds (default: 5)
  ROFI_WOOORDHUNT_WRAP_WIDTH   wrap width of the indented hint lines (default: 54)
  ROFI_WOOORDHUNT_HEAD_WIDTH   width the word line may reach before the gloss drops below (default: 58)
  ROFI_WOOORDHUNT_LOCALE       locale the wrapping counts characters in (default: the first UTF-8 one that works)
  ROFI_WOOORDHUNT_MODI         the modi to run (default: the one installed next to this script)
EOF
}

# Somebody pointed rofi at this launcher. Opening a rofi from inside rofi is refused by
# rofi itself, and being told so helps nobody — so step aside and let the modi answer, the
# way rofi expected in the first place. ROFI_RETV is set by rofi and nothing else
if [[ -n "${ROFI_RETV:-}" ]]; then
  exec "$MODI" "$@"
fi

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  # VERSION sits beside the script (the repo root in a checkout, share/rofi-wooordhunt
  # once installed) or one prefix over (the Nix package wraps the launcher into bin
  # while VERSION stays in share)
  -v | --version)
    self_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    for v in "$self_dir/VERSION" "$self_dir/../share/rofi-wooordhunt/VERSION"; do
      if [[ -f "$v" ]]; then
        printf 'rofi-wooordhunt %s\n' "$(cat "$v")"
        exit 0
      fi
    done
    printf 'rofi-wooordhunt unknown\n'
    exit 0
    ;;
  # The parser is off PATH, so this is the only way to name it from outside. Under Nix
  # it is the wrapper that gets named, not the script it wraps — the bare script would
  # find neither curl nor pup
  --modi)
    printf '%s\n' "$MODI"
    exit 0
    ;;
esac

# An array, not a bare \${1:+…}: a two-word query would otherwise split into two arguments
args=(-show "$MODE" -modi "$MODE:$MODI")
[[ $# -gt 0 ]] && args+=(-filter "$*")

exec rofi "${args[@]}"
