#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

usage() {
  cat <<EOF
install.sh — install the rofi-wooordhunt modi

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)

The script goes to \$PREFIX/share/rofi-wooordhunt, and \$PREFIX/bin gets a symlink to
it. Everything it needs — curl, pup, jq, a clipboard tool — comes from your PATH
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

install -d "$PREFIX/bin"
ln -sfn ../share/rofi-wooordhunt/rofi-wooordhunt.sh "$PREFIX/bin/rofi-wooordhunt"

echo "installed to $share, linked into $PREFIX/bin"
