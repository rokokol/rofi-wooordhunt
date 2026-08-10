#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

usage() {
  cat <<EOF
install.sh — install rofi-wooordhunt

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)

Both scripts go to \$PREFIX/share/rofi-wooordhunt, and \$PREFIX/bin gets a symlink to
the launcher only — the modi is rofi's to run, not yours. Everything they need — curl,
pup, jq, a clipboard tool — comes from your PATH
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?directory required}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
share="$PREFIX/share/rofi-wooordhunt"

install -Dm755 "$here/rofi-wooordhunt.sh" "$share/rofi-wooordhunt.sh"
install -Dm755 "$here/wooordhunt-modi.sh" "$share/wooordhunt-modi.sh"

install -d "$PREFIX/bin"
ln -sfn ../share/rofi-wooordhunt/rofi-wooordhunt.sh "$PREFIX/bin/rofi-wooordhunt"

echo "installed to $share, linked into $PREFIX/bin"
