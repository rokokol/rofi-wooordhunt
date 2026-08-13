# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where it was a launcher and a parser under the rofi directory

### Added

- the two-way dictionary: the direction is worked out from the query, transcriptions and synonym notes included
- the launcher and the script-modi it runs, with copy-to-clipboard
- `homeModules.default`, which supplies the bind and the modi name, and `overlays.default`
- checks: saved pages in and the rofi protocol out, diffed against goldens, plus the packaged command, its settings and module wiring
- `tests/live.sh` and a weekly `upstream.yml`: the live site is asked the same questions, then the saved set is re-downloaded and the offline suite runs against the fresh copy
