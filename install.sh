#!/usr/bin/env bash

set -euo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VERSION=$(cat "$here/VERSION")

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
PROMPT=""
COPY_COMMAND=""
WRAP_WIDTH=""
HEAD_WIDTH=""
TIMEOUT=""
UNINSTALL=0
config_given=""

usage() {
  cat <<EOF
install.sh — install rofi-wooordhunt $VERSION

Each run converges the prefix to exactly the flags given: re-running without a flag
undoes what that flag installed, the way unsetting a Nix option does on rebuild.

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

  -h, --help          show this help and exit
  -v, --version       print the version and exit
      --prefix DIR    install prefix (default: /usr/local)
      --destdir DIR   staging root: files land under DESTDIR/PREFIX
      --uninstall     remove everything a previous install wrote, by its manifest
      --prompt STR    bake a default rofi mode name into bin/rofi-wooordhunt
      --copy-command CMD
                      bake a default clipboard command (fed on stdin)
      --wrap-width N  bake a default wrap width of the indented hint lines
      --head-width N  bake a default width the word line may reach
      --timeout SEC   bake a default per-request timeout

Both scripts go to \$PREFIX/share/rofi-wooordhunt, and \$PREFIX/bin gets a symlink to
the launcher only — the modi is rofi's to run, not yours. The baking flags replace the
symlink with a short wrapper exporting the defaults; your own environment still wins,
like Nix's --set-default. A failed preflight names what is missing and prints your
distribution's own install command; nothing is installed on your behalf

Runtime environment (read by the installed scripts, not this script; the same knobs the
flags above bake — rofi-wooordhunt --help documents them all):
  ROFI_WOOORDHUNT_PROMPT, ROFI_WOOORDHUNT_COPY, ROFI_WOOORDHUNT_URL,
  ROFI_WOOORDHUNT_TIMEOUT, ROFI_WOOORDHUNT_WRAP_WIDTH, ROFI_WOOORDHUNT_HEAD_WIDTH,
  ROFI_WOOORDHUNT_LOCALE, ROFI_WOOORDHUNT_MODI
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
    --prompt)
      PROMPT="${2:?value required by $1}"
      config_given="$1"
      shift 2
      ;;
    --copy-command)
      COPY_COMMAND="${2:?value required by $1}"
      config_given="$1"
      shift 2
      ;;
    --wrap-width)
      WRAP_WIDTH="${2:?value required by $1}"
      config_given="$1"
      shift 2
      ;;
    --head-width)
      HEAD_WIDTH="${2:?value required by $1}"
      config_given="$1"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:?value required by $1}"
      config_given="$1"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -v | --version)
      echo "rofi-wooordhunt $VERSION"
      exit 0
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

if [[ "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute: $PREFIX" >&2
  exit 1
fi
if ((UNINSTALL)) && [[ -n "$config_given" ]]; then
  echo "install.sh: --uninstall does not combine with $config_given" >&2
  exit 1
fi
for number in "$WRAP_WIDTH" "$HEAD_WIDTH" "$TIMEOUT"; do
  if [[ -n "$number" && ! "$number" =~ ^[0-9]+$ ]]; then
    echo "install.sh: a number is required: $number" >&2
    exit 1
  fi
done

root="${DESTDIR%/}$PREFIX"
share_runtime="$PREFIX/share/rofi-wooordhunt"
share="${DESTDIR%/}$share_runtime"
manifest="$share/install-manifest"

# --- uninstall -------------------------------------------------------------------------

if ((UNINSTALL)); then
  if [[ ! -f "$manifest" ]]; then
    # Installs made before the manifest existed (rofi-wooordhunt <= 1.0.1): the fixed
    # list those versions wrote. Drop this arm one release later
    rm -f "$root/bin/rofi-wooordhunt"
    rm -rf "$share"
    echo "removed rofi-wooordhunt from $root"
    exit 0
  fi
  while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    rm -f "${DESTDIR%/}$path"
  done <"$manifest"
  rm -f "$manifest"
  rmdir "$share" 2>/dev/null || true
  echo "removed rofi-wooordhunt from $root"
  exit 0
fi

# --- preflight: refuse loudly, install nothing ----------------------------------------
# The parser's own tools have to exist; rofi and the clipboard come from the session,
# so their absence warns and the install proceeds

missing=()
absent=()

need() { command -v "$1" >/dev/null 2>&1 || missing+=("$1"); }
want() { command -v "$1" >/dev/null 2>&1 || absent+=("$1"); }

need install
need curl
need pup
need jq
need gawk
need xargs
want rofi
want wl-copy

distro_id() {
  sed -n 's/^ID\(_LIKE\)\?=//p' "$OS_RELEASE" 2>/dev/null | tr -d '"' | tr '\n' ' '
}

# Missing commands become the distribution's own package names, printed as runnable
# `  $ command` lines — the distro tests run exactly these, so a typo here is a red
# run. pup is the odd one out: no distribution archive carries it except the AUR, so
# everywhere else the ONE recommended way is go install, pinned to a system-wide GOBIN.
# @master, not @latest: the v0.4.0 tag predates go.mod, so @latest resolves fresh
# dependencies (some now demanding a newer go than Debian ships) and misses four years
# of parser fixes — master is the code nixpkgs and the AUR package both build
pkg_for() {
  case "$1" in
    xargs) echo findutils ;;
    *) echo "$1" ;;
  esac
}

if ((${#missing[@]})); then
  pkgs=()
  pup_missing=0
  for command in "${missing[@]}"; do
    if [[ "$command" == pup ]]; then
      pup_missing=1
    else
      pkgs+=("$(pkg_for "$command")")
    fi
  done
  {
    printf 'install.sh: missing dependencies:\n'
    printf '  - %s\n' "${missing[@]}"
    case " $(distro_id) " in
      *" arch "*)
        if ((${#pkgs[@]})); then
          printf '\nInstall them on Arch:\n'
          printf '  $ sudo pacman -S --needed %s\n' "${pkgs[*]}"
        fi
        if ((pup_missing)); then
          printf '\nInstall pup on Arch, from the AUR:\n'
          printf '  $ paru -S pup\n'
        fi
        ;;
      *" debian "* | *" ubuntu "*)
        printf '\nInstall them on Debian/Ubuntu:\n'
        printf '  $ sudo apt-get update\n'
        if ((${#pkgs[@]})); then
          printf '  $ sudo apt-get install %s\n' "${pkgs[*]}"
        fi
        if ((pup_missing)); then
          printf '  $ sudo apt-get install golang-go\n'
          printf '  $ sudo GOBIN=/usr/local/bin go install github.com/ericchiang/pup@master\n'
        fi
        ;;
      *" fedora "*)
        printf '\nInstall them on Fedora:\n'
        if ((${#pkgs[@]})); then
          printf '  $ sudo dnf install %s\n' "${pkgs[*]}"
        fi
        if ((pup_missing)); then
          printf '  $ sudo dnf install golang\n'
          printf '  $ sudo GOBIN=/usr/local/bin go install github.com/ericchiang/pup@master\n'
        fi
        ;;
      *)
        printf '\nInstall them with your package manager: %s\n' "${pkgs[*]}"
        if ((pup_missing)); then
          printf '  https://github.com/ericchiang/pup\n'
        fi
        ;;
    esac
  } >&2
  exit 1
fi
if ((${#absent[@]})); then
  printf 'install.sh: not found (comes from your session, install proceeds): %s\n' \
    "${absent[@]}" >&2
fi

# --- install ---------------------------------------------------------------------------
# Every file lands in the manifest as its final runtime path (no DESTDIR); paths a
# previous install wrote that this run does not are swept at the end, which is what
# makes the flags declarative

old_paths=()
if [[ -f "$manifest" ]]; then
  mapfile -t old_paths < <(grep -v '^#' "$manifest")
fi

installed=()
rec() { installed+=("${1#"${DESTDIR%/}"}"); }

install -Dm755 "$here/rofi-wooordhunt.sh" "$share/rofi-wooordhunt.sh"
rec "$share/rofi-wooordhunt.sh"
install -Dm755 "$here/wooordhunt-modi.sh" "$share/wooordhunt-modi.sh"
rec "$share/wooordhunt-modi.sh"
install -Dm644 "$here/VERSION" "$share/VERSION"
rec "$share/VERSION"

# bin carries a relative symlink, until a flag bakes an environment default — then a
# wrapper takes its place, with ${VAR:-...} so the caller's environment still wins
install -d "$root/bin"
bake() { # bake VAR VALUE — one export line of the wrapper, skipped when VALUE is empty
  if [[ -n "$2" ]]; then
    echo "export $1=\"\${$1:-$2}\""
  fi
}
if [[ -n "$PROMPT$COPY_COMMAND$WRAP_WIDTH$HEAD_WIDTH$TIMEOUT" ]]; then
  rm -f "$root/bin/rofi-wooordhunt"
  {
    echo '#!/bin/sh'
    bake ROFI_WOOORDHUNT_PROMPT "$PROMPT"
    bake ROFI_WOOORDHUNT_COPY "$COPY_COMMAND"
    bake ROFI_WOOORDHUNT_WRAP_WIDTH "$WRAP_WIDTH"
    bake ROFI_WOOORDHUNT_HEAD_WIDTH "$HEAD_WIDTH"
    bake ROFI_WOOORDHUNT_TIMEOUT "$TIMEOUT"
    echo "exec \"$share_runtime/rofi-wooordhunt.sh\" \"\$@\""
  } >"$root/bin/rofi-wooordhunt"
  chmod 755 "$root/bin/rofi-wooordhunt"
else
  ln -sfn ../share/rofi-wooordhunt/rofi-wooordhunt.sh "$root/bin/rofi-wooordhunt"
fi
rec "$PREFIX/bin/rofi-wooordhunt"

# The declarative sweep: whatever the previous install wrote and this one did not
for path in "${old_paths[@]}"; do
  keep=0
  for now in "${installed[@]}"; do
    [[ "$path" == "$now" ]] && keep=1
  done
  ((keep)) || rm -f "${DESTDIR%/}$path"
done

{
  echo "# rofi-wooordhunt $VERSION install manifest"
  printf '%s\n' "${installed[@]}"
} >"$manifest"

echo "installed rofi-wooordhunt $VERSION to $share, linked into $root/bin"
