# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [1.1.0] - 2026-08-31

### Added

- a `VERSION` file as the one place the version lives: `nix/package.nix` reads it, `rofi-wooordhunt --version`/`-v` and `./install.sh --version`/`-v` print it, and CI refuses a release whose `CHANGELOG.md` has no heading for it
- installer flags mirroring the package options — `--prompt`, `--copy-command`, `--wrap-width`, `--head-width`, `--timeout` — which swap the bin symlink for a short wrapper exporting the defaults, the caller's environment still winning; a re-run without them puts the symlink back
- `--uninstall` by manifest: the install writes `share/rofi-wooordhunt/install-manifest` naming every file it created, and uninstall consumes it — installs made before the manifest are still removed by a fixed list for one release
- a dependency preflight that installs nothing on its own: missing tools are named with the distribution's own install command as a runnable `$` line; pup, which no distribution archive carries, comes from the AUR on Arch (`paru -S pup`) and from a system-wide `go install` everywhere else; rofi and the clipboard only warn, because they come from the session
- tab completion for `install.sh` itself (`source completions/install.sh.bash` or `.zsh`), with a drift check that fails the lint when a flag exists in only one of the three places
- distro tests: `tests/distro.sh` installs for real, as root, in `debian`/`ubuntu`/`archlinux`/`fedora` `:latest` containers by running the preflight's own printed guidance — the Arch run builds pup from its AUR clone, the documented equivalent of the printed `paru -S pup`, which is the one line a base container cannot run literally — then drives the golden suite against the installed copies and uninstalls by the manifest; CI runs them on every push to master and weekly, never on pull requests, with one README badge per distribution

### Fixed

- the UTF-8 probe asks a child bash instead of `wc -m`: Ubuntu's coreutils are uutils now, whose wc counts UTF-8 characters regardless of the locale — it vouched for a locale bash never got, and the whole layout fell back to byte counting. Found by the distro suite's first Ubuntu run
- the gloss capture is spelled `(capture(...) | .g)?` instead of `capture(...)?.g`: Debian ships jq 1.7, which cannot parse the postfix-`?` field chain, and the error vanished into a `2>/dev/null` — every Russian query lost its sections there. Found by the distro suite's first Debian run

### Changed

- the shell lint's file list lives only in the flake's `scripts-lint` check; the CI shell job builds that check instead of repeating the commands

## [1.0.1] - 2026-08-18

### Changed

- `install.sh` accepts `DESTDIR` independently of `PREFIX`, so package recipes can stage its canonical layout

### Fixed

- the Nix package version follows the latest release instead of the pre-release script version
- the `1.0.0` notes no longer claim that the Home Manager module supplies a key binding

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where it was a launcher and a parser under the rofi directory

### Added

- the two-way dictionary: the direction is worked out from the query, transcriptions and synonym notes included
- the launcher and the script-modi it runs, with copy-to-clipboard
- `homeModules.default`, which installs the package, and `overlays.default`
- checks: saved pages in and the rofi protocol out, diffed against goldens, plus the packaged command, its settings and module wiring
- `tests/live.sh` and a weekly `upstream.yml`: the live site is asked the same questions, then the saved set is re-downloaded and the offline suite runs against the fresh copy
- a failed lookup explains itself on the message line and puts the raw cause in the row, where a bare `---` used to be — curl's own line, or the URL that came back unreadable, copyable with Enter
