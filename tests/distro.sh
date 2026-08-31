#!/usr/bin/env bash
# Distro tests for rofi-wooordhunt: run install.sh for real, as root, inside a container
# of an actual distribution — the one thing tests/run.sh cannot do. Here the real
# package manager provides curl, jq, gawk and findutils by running the very commands
# the preflight printed when it refused — and pup, which no distribution archive
# carries: the AUR on Arch, a system-wide go install everywhere else. rofi and the
# clipboard are session dependencies the preflight only warns about.
#
#   tests/distro.sh              every distribution below
#   tests/distro.sh debian       just one
#
# Needs docker or podman. In CI this runs on push to master, weekly, and by hand — never
# on pull requests: a flaky mirror must not redden someone's change. Images are :latest
# on purpose — the weekly run is the upstream-drift detector, so no assertion may depend
# on what an image happens to carry already
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")

declare -A IMAGE=(
  [debian]=docker.io/library/debian:latest
  [ubuntu]=docker.io/library/ubuntu:latest
  [arch]=docker.io/library/archlinux:latest
  [fedora]=docker.io/library/fedora:latest
)

INSTALL_FLAGS=()

# Bootstrap: only what the harness itself needs in a minimal image — never a dependency
# the preflight's guidance is supposed to provide, or the guidance test would pass
# because the answer was planted. Arch needs its sync database refreshed (the printed
# pacman -S cannot work against an empty one); arch and fedora both strip the diff the
# golden comparisons in the suite use
declare -A BOOTSTRAP=(
  [debian]=':'
  [ubuntu]=':'
  [arch]='pacman -Sy --noconfirm --needed diffutils'
  [fedora]='dnf install -y -q diffutils'
)

smoke() { # runs inside the container after a successful install
  local prefix="$1"
  "$prefix/bin/rofi-wooordhunt" --version | grep -qxF "rofi-wooordhunt $(cat VERSION)"
  # --modi names the parser the launcher would hand rofi, and it has to exist
  test -x "$("$prefix/bin/rofi-wooordhunt" --modi)"
  # The whole golden suite against the installed copies — curl stays stubbed by the
  # suite itself, so nothing here talks to the site
  ROFI_WOOORDHUNT="$prefix/bin/rofi-wooordhunt" \
    ROFI_WOOORDHUNT_MODI="$prefix/share/rofi-wooordhunt/wooordhunt-modi.sh" \
    ./tests/run.sh >/dev/null
}

# ======================================================================================
# host half: find an engine, pull fresh, re-execute this script inside the container
# ======================================================================================

if [[ "${1:-}" != "--inside" ]]; then
  engine=""
  for candidate in "${CONTAINER_ENGINE:-}" docker podman; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" >/dev/null && "$candidate" info >/dev/null 2>&1; then
      engine="$candidate"
      break
    fi
  done
  if [[ -z "$engine" ]]; then
    echo "tests/distro.sh: needs a working docker or podman" >&2
    exit 1
  fi

  wanted=("$@")
  ((${#wanted[@]})) || wanted=(debian ubuntu arch fedora)

  fails=0
  for distro in "${wanted[@]}"; do
    image="${IMAGE[$distro]:-}"
    if [[ -z "$image" ]]; then
      echo "tests/distro.sh: no such distribution: $distro" >&2
      exit 1
    fi
    printf '\n== %s (%s)\n' "$distro" "$image"
    # One retry on the pull: a mirror hiccup is not a verdict on anything
    "$engine" pull -q "$image" >/dev/null || "$engine" pull -q "$image" >/dev/null
    # The checkout goes in read-only — the run must not be able to edit it
    if ! "$engine" run --rm -v "$REPO:/src:ro" "$image" \
      bash /src/tests/distro.sh --inside "$distro"; then
      printf '  %s: FAILED\n' "$distro"
      fails=$((fails + 1))
    else
      printf '  %s: passed\n' "$distro"
    fi
  done
  ((fails)) && exit 1
  echo
  echo "all distributions passed"
  exit 0
fi

# ======================================================================================
# container half
# ======================================================================================

distro="$2"

say() { printf '\n  -- %s\n' "$1"; }
die() {
  printf '  !! %s\n' "$1" >&2
  exit 1
}

# The documented equivalent of `paru -S <pkgs>`, for the one arm whose printed line
# cannot run: paru itself lives in the AUR, so a base container has no way to have it.
# base-devel, a throwaway builder (makepkg refuses root), the package's own depends
# read from its PKGBUILD and installed by pacman, makepkg without -si, pacman -U as root
aur_install() {
  pacman -S --noconfirm --needed base-devel git >/dev/null
  id builder >/dev/null 2>&1 || useradd -m builder
  local pkg deps
  for pkg in "$@"; do
    runuser -u builder -- git clone --depth 1 \
      "https://aur.archlinux.org/$pkg.git" "/home/builder/$pkg"
    deps=$(runuser -u builder -- bash -c \
      "cd /home/builder/$pkg && source PKGBUILD >/dev/null 2>&1; echo \"\${makedepends[*]:-} \${depends[*]:-}\"")
    local dep_list=()
    read -ra dep_list <<<"$deps"
    if ((${#dep_list[@]})); then
      pacman -S --noconfirm --needed "${dep_list[@]}" >/dev/null
    fi
    runuser -u builder -- bash -c "cd /home/builder/$pkg && makepkg --noconfirm" >/dev/null
    pacman -U --noconfirm "/home/builder/$pkg"/*.pkg.tar* >/dev/null
  done
}

say "bootstrap ($distro)"
bash -c "${BOOTSTRAP[$distro]}" >/dev/null

# The checkout is mounted read-only; work on a copy a package manager cannot be blamed for
cp -r /src /work
cd /work

prefix=/usr/local
bin_path="$prefix/bin/rofi-wooordhunt"
share_dir="$prefix/share/rofi-wooordhunt"

say "a relative PREFIX is rejected"
! PREFIX=usr ./install.sh "${INSTALL_FLAGS[@]}" >/dev/null 2>&1 ||
  die "install.sh accepted a relative PREFIX"

say "install, running the printed guidance when the preflight refuses"
rc=0
out=$(./install.sh "${INSTALL_FLAGS[@]}" 2>&1) || rc=$?
if ((rc != 0)); then
  # The refusal must be complete and clean: name what is missing, write nothing
  printf '%s\n' "$out" | grep -q 'missing dependencies' ||
    die "the refusal did not say what is missing: $out"
  [[ ! -e "$bin_path" && ! -e "$share_dir" ]] ||
    die "a refused install left files behind"
  printf '%s\n' "$out" | grep -qE 'command not found|: line [0-9]' &&
    die "the preflight listed what is missing and then carried on: $out"

  # Runnable guidance lines are `  $ command`; they are run exactly as printed.
  # Non-interactivity is arranged around the command — DEBIAN_FRONTEND, yes on stdin —
  # never inside it: the printed line has no -y because a human reads it
  commands=$(printf '%s\n' "$out" | sed -n 's/^  \$ //p')
  if [[ -z "$commands" ]]; then
    echo "::notice title=rofi-wooordhunt distro test::SKIP on $distro — guidance is manual-only"
    printf '  SKIP: no runnable guidance on %s\n' "$distro"
    exit 0
  fi
  # The container is root and none of these images ships sudo. Answered with a shim, not
  # by editing the line: a sudo can sit mid-pipeline (| sudo tee) where stripping a
  # prefix cannot reach, and an edited line is no longer the line the reader was given.
  # exec env, not exec: a printed line may carry VAR=value assignments after sudo
  # (GOBIN=... go install), and env is what gives those effect
  if ! command -v sudo >/dev/null; then
    printf '#!/bin/sh\nexec env "$@"\n' >/usr/local/bin/sudo
    chmod +x /usr/local/bin/sudo
  fi
  export DEBIAN_FRONTEND=noninteractive
  while IFS= read -r cmd; do
    printf '  running printed guidance: %s\n' "$cmd"
    case "$cmd" in
      "paru -S "*)
        read -ra aur_pkgs <<<"${cmd#paru -S }"
        aur_install "${aur_pkgs[@]}" || die "the AUR build failed for: $cmd"
        ;;
      *)
        # yes answers "y" to [Y/n]-style prompts; dnf treats an empty answer as No.
        # Fed by process substitution, not a pipe: pipefail would turn yes's own
        # SIGPIPE death into a failed pipeline
        bash -c "$cmd" < <(yes 2>/dev/null) || die "printed guidance failed: $cmd"
        ;;
    esac
  done <<<"$commands"

  say "install succeeds once the guidance has been followed"
  ./install.sh "${INSTALL_FLAGS[@]}" || die "install failed after following the guidance"
else
  echo "  (every dependency was already present — the refusal path ran elsewhere)"
fi

say "the installed tool answers"
[[ -e "$bin_path" ]] || die "no $bin_path after install"
[[ -f "$share_dir/install-manifest" ]] || die "no install-manifest after install"
./install.sh --help >/dev/null || die "--help failed"
smoke "$prefix" || die "smoke test failed"

say "uninstall removes exactly what the manifest names"
mapfile -t manifest_paths < <(grep -v '^#' "$share_dir/install-manifest")
./install.sh --uninstall "${INSTALL_FLAGS[@]}" || die "--uninstall failed"
for path in "${manifest_paths[@]}"; do
  [[ ! -e "$path" && ! -L "$path" ]] || die "uninstall left $path behind"
done
[[ ! -e "$share_dir" ]] || die "uninstall left $share_dir behind"

say "a second uninstall is quiet and succeeds"
./install.sh --uninstall "${INSTALL_FLAGS[@]}" >/dev/null || die "uninstall is not idempotent"

echo
echo "  $distro: full cycle passed"
