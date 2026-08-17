#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"

usage() {
  cat <<EOF
install.sh — install rofi-wooordhunt

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

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
    --destdir)
      DESTDIR="${2:?directory required}"
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

if [[ -n "$DESTDIR" && "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute when DESTDIR is set: $PREFIX" >&2
  exit 1
fi

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
root="${DESTDIR%/}$PREFIX"
share="$root/share/rofi-wooordhunt"

install -Dm755 "$here/rofi-wooordhunt.sh" "$share/rofi-wooordhunt.sh"
install -Dm755 "$here/wooordhunt-modi.sh" "$share/wooordhunt-modi.sh"

install -d "$root/bin"
ln -sfn ../share/rofi-wooordhunt/rofi-wooordhunt.sh "$root/bin/rofi-wooordhunt"

echo "installed to $share, linked into $root/bin"
