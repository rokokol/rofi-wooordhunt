#!/usr/bin/env bash
# tests/distro.sh is what checks a full distribution actually satisfies the printed
# guidance (see CLAUDE.md)
set -euo pipefail

usage() {
  cat <<'EOF'
tests/installer.sh — the fast suite for install.sh: flag surface and exit codes, a
real install and uninstall into a temp --prefix, and the preflight refusal —
everything that needs no docker container

  tests/installer.sh [REPO]

REPO is the checkout to install from (default: the one this script lives in)

Nothing here reaches the network
Exit: 0 all passed, 1 a check failed
EOF
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]] && {
  usage
  exit 0
}

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO="${1:-$(dirname "$HERE")}"

fails=0
say() { printf -- '-- %s\n' "$1"; }
die() {
  printf '!! %s\n' "$1" >&2
  fails=$((fails + 1))
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

prefix="$tmp/prefix"
share="$prefix/share/rofi-wooordhunt"
bin_path="$prefix/bin/rofi-wooordhunt"
manifest="$share/install-manifest"
run() { "$REPO/install.sh" --prefix "$prefix" "$@"; }

say "--help names every flag the case parses, and -v matches VERSION"
mapfile -t flags < <(
  sed -n 's/^ *\(-[-a-zA-Z0-9 |]*\))$/\1/p' "$REPO/install.sh" |
    tr '|' '\n' | tr -d ' ' | sort -u
)
((${#flags[@]})) || die "found no flags in install.sh — the extractor is broken"
help_out=$("$REPO/install.sh" --help)
for flag in "${flags[@]}"; do
  grep -qF -- "$flag" <<<"$help_out" || die "--help does not mention $flag"
done
[[ "$("$REPO/install.sh" -v)" == "rofi-wooordhunt $(cat "$REPO/VERSION")" ]] ||
  die "-v does not print 'rofi-wooordhunt \$(cat VERSION)'"

say "bad arguments are refused with exit 2, the usage-error code"
rc=0
run --no-such-flag >/dev/null 2>&1 || rc=$?
((rc == 2)) || die "an unknown flag exited $rc, not the usage-error code 2"
rc=0
"$REPO/install.sh" --prefix relative/path >/dev/null 2>&1 || rc=$?
((rc == 2)) || die "a relative --prefix exited $rc, not the usage-error code 2"
rc=0
"$REPO/install.sh" --prefix >/dev/null 2>&1 || rc=$?
((rc == 2)) || die "--prefix given last with no value exited $rc, not the usage-error code 2"

say "--uninstall refuses to combine with a baking flag"
for pair in "--prompt:x" "--copy-command:x" "--wrap-width:5" "--head-width:5" "--timeout:5"; do
  flag="${pair%%:*}"
  value="${pair#*:}"
  rc=0
  run --uninstall "$flag" "$value" >/dev/null 2>&1 || rc=$?
  ((rc == 2)) || die "--uninstall combined with $flag exited $rc, not the usage-error code 2"
done

say "a non-numeric --wrap-width/--head-width/--timeout is refused"
for flag in --wrap-width --head-width --timeout; do
  rc=0
  run "$flag" nope >/dev/null 2>&1 || rc=$?
  ((rc == 2)) || die "a non-numeric $flag exited $rc, not the usage-error code 2"
done

say "the preflight refuses a system missing install(1), with a stubbed PATH"
stub="$tmp/bin"
mkdir -p "$stub"
for tool in bash cat chmod dirname grep readlink rm rmdir sed tr curl gawk jq pup xargs; do
  ln -s "$(command -v "$tool")" "$stub/$tool"
done
rm -f "$stub/install"               # the one dependency this run is missing
echo "ID=debian" >"$tmp/os-release" # the flake-check sandbox has no /etc/os-release
rc=0
out=$(OS_RELEASE="$tmp/os-release" PATH="$stub" bash "$REPO/install.sh" \
  --prefix "$prefix" 2>&1) || rc=$?
((rc == 1)) || die "the preflight exited $rc, not the missing-dependency code 1"
grep -q 'missing dependencies' <<<"$out" || die "the refusal did not say what is missing"
grep -q ' - install$' <<<"$out" || die "the refusal did not name install(1)"
grep -qE '^  \$ ' <<<"$out" || die "the refusal printed no runnable guidance"
[[ ! -e "$bin_path" && ! -e "$share" ]] || die "a refused install wrote files"

say "a real install into a temp --prefix lands the files and the manifest"
run >/dev/null
[[ -e "$bin_path" ]] || die "no $bin_path after install"
[[ -f "$share/rofi-wooordhunt.sh" ]] || die "the launcher was not installed"
[[ -f "$share/wooordhunt-modi.sh" ]] || die "the modi was not installed"
[[ -f "$share/VERSION" ]] || die "VERSION was not installed"
[[ -f "$manifest" ]] || die "no install-manifest after install"
"$bin_path" --version | grep -qxF "rofi-wooordhunt $(cat "$REPO/VERSION")" ||
  die "the installed launcher does not answer --version"

say "--uninstall removes exactly what the manifest lists"
mapfile -t manifest_paths < <(grep -v '^#' "$manifest")
((${#manifest_paths[@]})) || die "the manifest named nothing to remove"
run --uninstall >/dev/null
for path in "${manifest_paths[@]}"; do
  [[ ! -e "$path" && ! -L "$path" ]] || die "uninstall left $path behind"
done
[[ ! -e "$share" ]] || die "uninstall left $share behind"

echo
if ((fails)); then
  echo "$fails failure(s)"
  exit 1
fi
echo "all install.sh checks passed"
