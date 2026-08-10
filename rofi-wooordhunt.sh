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

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

# An array, not a bare \${1:+…}: a two-word query would otherwise split into two arguments
args=(-show "$MODE" -modi "$MODE:$MODI")
[[ $# -gt 0 ]] && args+=(-filter "$*")

exec rofi "${args[@]}"
