# CLAUDE.md

## What this repo is

A two-way dictionary in rofi, parsing [wooordhunt.ru](https://wooordhunt.ru). It works out the direction itself. `rofi-wooordhunt.sh` is the launcher — the only thing on `PATH` — and `wooordhunt-modi.sh` is the script-modi that fetches, parses and prints the rofi protocol

The seam in `rokokol/huix` is `home-manager/desktop/hyprland/services/rofi-wooordhunt.nix`: enabling the module and the emoji prompt. The `SUPER+Y` bind and the modi name come from the module

`README.md` is Russian here and `README.en.md` is the translation — the subject is an English dictionary for a Russian speaker, so the reader is the language. Everything else, including this file, is English

## Build / check

```sh
nix build
nix flake check          # tests, the packaged command, its settings, module wiring, shell lint
./tests/run.sh           # saved pages in, the rofi protocol out, diffed against tests/golden
./tests/live.sh          # the real site, checking the shape of the answer (needs the network)
./tests/refresh.sh out   # re-download the saved set
./tests/distro.sh debian # real root install in docker; also ubuntu, arch, fedora
nix fmt -- --ci
```

## Layout

```
rofi-wooordhunt.sh   the launcher: the only thing on PATH, runs rofi with the modi
wooordhunt-modi.sh   the modi: query, parse, rofi protocol out
VERSION              the one place the version lives — package.nix, --version and CI read it
completions/         install.sh's own completions, spelled by hand
nix/                 package.nix, module.nix, module-test.nix
tests/               run.sh, live.sh, refresh.sh, distro.sh, check-completions.sh, fixtures, goldens
docs/                the screenshots
install.sh           for systems without Nix
```

## Things that will bite

- **offline fixtures rot silently.** A saved page parses forever after the site has stopped looking like it, which is why `tests/live.sh` and the weekly `upstream.yml` exist: the workflow asks the live site the same questions and then re-downloads the set and runs the offline suite against the fresh copy. The criterion is the parsed output, not the HTML
- **`fold` counts characters only from coreutils 9.8.** On anything older it cuts Cyrillic by bytes and no locale fixes it, so wrapping is done in bash
- **`${#s}` is locale-dependent**, so the script picks a UTF-8 locale itself — and verifies it in a **child bash** (`bash -c 's=ä; echo ${#s}'`), because bash keeps its old locale when `setlocale` rejects a name while still exporting the rejected value. A child *bash* and not `wc -m`: bash is what counts downstream, and uutils' wc (Ubuntu's coreutils now) counts UTF-8 characters regardless of the locale, so it vouches for a locale bash never got
- **the stub guard is not decoration.** `tests/run.sh` refuses to start unless every file in `tests/stub/` is executable and first on `PATH`; for `curl` that is the difference between an offline suite and one quietly going to the network

## CHANGELOG

Every user-visible change adds a bullet under `## [Unreleased]` in `CHANGELOG.md`. A release moves those bullets under a new version heading with the date **and bumps `VERSION` in the same commit** — CI refuses a `VERSION` whose heading is missing — then tags `v<x.y.z>` and cuts a `gh release` whose notes are that section. Dates belong in this file and nowhere else — the no-dates rule holds everywhere but here, because Keep a Changelog asks for them
