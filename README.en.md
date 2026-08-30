<div align="center">

# rofi-wooordhunt

**Wooordhunt rofi parser** 🤓

![rofi](https://img.shields.io/badge/rofi-script--modi-F4A100?style=flat)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/rofi-wooordhunt/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/rofi-wooordhunt/actions/workflows/build.yml)

[Русский](README.md)

</div>

A parser for [wooordhunt.ru](https://wooordhunt.ru). Works out the translation direction itself

Came over from my rice, **[rokokol/huix](https://github.com/rokokol/huix)**

```sh
# try it on the running session without installing anything
nix run github:rokokol/rofi-wooordhunt
```

## Contents

- [What you get back](#what-you-get-back)
- [Install](#install)
  - [Home Manager](#home-manager)
  - [Any other distribution](#any-other-distribution)
  - [Two files, one on PATH](#two-files-one-on-path)
- [Settings](#settings)
- [How it works](#how-it-works)
- [Tests](#tests)
- [Layout](#layout)

## What you get back

**Russian in** — the English words, each with its own transcription, its gloss list, and the site's explanation of when to pick this one over its synonyms:

![A Russian query](docs/screenshot-ru.png)

That explanation is what makes the Russian direction worth having: a list of six synonyms says nothing about which one a native speaker would reach for, and this one does. The indented lines are **non-selectable** — arrow keys skip them, so the explanation reads as a note under the word rather than as nine more things to choose from

**English in** — the transcriptions in the header, one per part of speech when the spelling covers several words, and the meanings as rows:

![An English query](docs/screenshot-en.png)

Enter copies the entry. On a word with an explanation it copies the **word**, not the line you were looking at

Multi-word phrases work too. The space becomes the underscore the site expects:

![A phrase](docs/screenshot-phrase.png)

_Theme — [ddlc-rofi-theme](https://github.com/rokokol/ddlc-rofi-theme)_

## Install

### Home Manager

```nix
{
  inputs.rofi-wooordhunt.url = "github:rokokol/rofi-wooordhunt";

  # in your home configuration
  imports = [ inputs.rofi-wooordhunt.homeManagerModules.default ];

  programs.rofi-wooordhunt.enable = true;
}
```

That installs the package and stops there. The mode names itself through the script protocol

| option                    | what it does                                         | default     |
| -------------------------- | ---------------------------------------------------- | ------------ |
| `prompt`                  | what rofi shows as the mode name                    | `🤓`        |
| `copyCommand`             | fed the picked entry on stdin                       | `wl-copy`   |
| `wrapWidth` / `headWidth` | where the lines wrap; widen both for a wider window | `54` / `58` |
| `timeout`                 | seconds a request may take                          | `5`         |

### Any other distribution

```sh
git clone https://github.com/rokokol/rofi-wooordhunt
cd rofi-wooordhunt
sudo ./install.sh          # PREFIX=~/.local ./install.sh for a user install
```

Nothing is built: both scripts are copied to `$PREFIX/share/rofi-wooordhunt`, and only the launcher is symlinked into `$PREFIX/bin`

A package recipe can stage the same files without duplicating that logic: `DESTDIR="$pkgdir" PREFIX=/usr ./install.sh`

Needs `bash`, `curl`, [`pup`](https://github.com/ericchiang/pup), `jq`, `awk`, `sed`, `grep`, `xargs`, and a clipboard tool — `wl-copy` by default, `ROFI_WOOORDHUNT_COPY="xclip -selection clipboard"` on X11

Then bind it by hand:

```conf
bind = SUPER, Y, exec, rofi-wooordhunt
```

### Two files, one on PATH

`rofi-wooordhunt` is a **launcher**: it starts rofi and hands it the parser as a script modi, by absolute path. The parser — `wooordhunt-modi` — sits in `libexec` and never appears on PATH, because rofi runs it for every keystroke and nobody types it by hand. That is the whole reason the bind is one word instead of a `rofi -show … -modi "…"` incantation copied into every config that wants the dictionary.

A query given on the command line becomes rofi's initial filter, so `rofi-wooordhunt транзистор` opens with the search line already filled.

It is also a **mode of your own rofi**, next to whatever else you keep there — point rofi at the launcher and it steps aside for the parser:

```sh
rofi -show dictionary -modi "dictionary:rofi-wooordhunt,emoji:rofimoji"
```

That detour exists because rofi refuses to run inside rofi (it keeps the outer pid in `ROFI_OUTSIDE` and checks it is still alive), so a launcher that finds `ROFI_RETV` in its environment knows it was mistaken for a mode, and hands the job to the parser rather than to a rofi that would never start.

`rofi-wooordhunt --modi` prints where that parser is, which the line above does not need. Under Nix that path is the `makeWrapper` wrapper, not the script it wraps: the bare script would find neither `curl` nor `pup`.

## Settings

Every Home Manager option above is an environment variable underneath, so the same knobs work without Nix:

| variable                     | what it sets                                                                                                               |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `ROFI_WOOORDHUNT_PROMPT`     | the mode name rofi shows                                                                                                   |
| `ROFI_WOOORDHUNT_COPY`       | the clipboard command                                                                                                      |
| `ROFI_WOOORDHUNT_WRAP_WIDTH` | width the indented explanation wraps at                                                                                    |
| `ROFI_WOOORDHUNT_HEAD_WIDTH` | width the word line may reach before its gloss drops below                                                                 |
| `ROFI_WOOORDHUNT_TIMEOUT`    | per-request timeout in seconds                                                                                             |
| `ROFI_WOOORDHUNT_URL`        | the site root, for pointing the modi at a mirror or a fixture tree                                                         |
| `ROFI_WOOORDHUNT_LOCALE`     | the locale the wrapping counts characters in; unset, the modi takes the first UTF-8 locale the machine actually answers to |

The wrapping is ours because **rofi rows are single-line**: text that does not fit is truncated with `…`, never wrapped, so a long explanation has to be broken into rows by hand. That makes both widths a function of your window width — the defaults are for 720px

`rofi-wooordhunt --help` prints the same list. Typed into the search field it is just a query — the parser has no options of its own, every argument it gets is a word to look up

## How it works

There is no API. The modi fetches the page and reads it with `pup` and `jq`, which is enough because the markup is regular — but the site has **four different shapes** for what is nominally the same answer, and the parser walks them in order:

| the page has        | is                                                                               | shows as                                                                                                        |
| -------------------- | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `section.sub_entry` | the Russian direction: synonym groups, each with a gloss list and an explanation | word + transcription, explanation indented below                                                                |
| `.t_inline_en`      | the English direction, meanings on one line                                      | one row per meaning                                                                                             |
| `.tr > span`        | the English direction, one meaning per span                                      | one row per meaning, the span markup collapsed by hand so `<i>(чрезмерно)</i> подчёркивать` stays one meaning |
| `.light_tr`         | a phrase page                                                                    | the translation as a single row                                                                                 |

Transcriptions live in a different block than the meanings (`.trans_sound`), and the Russian direction carries none at all — so for a Russian query the modi fetches the word page of **every** English result, in parallel, purely for the transcription. A word whose page does not answer simply appears without one

Homographs are why that block is walked rather than grepped: `transfer` is two words with two pronunciations sharing one page, and a `grep` for the first `.transcription` would confidently show you the wrong one

## Tests

```sh
tests/run.sh              # 19 checks, no network
tests/run.sh --update     # re-record the golden output after a deliberate change
tests/live.sh             # the same questions, asked of the real site
tests/refresh.sh [dir]    # re-download the saved pages named in routes
```

`tests/run.sh` puts a stub `curl` on PATH that serves saved pages from `tests/fixtures` according to `tests/fixtures/routes`, and diffs the rofi protocol the modi emits against `tests/golden` — so a change in how an answer is assembled shows up as a diff. Two reserved slugs stand in for the failures a saved page cannot express, a timeout and a transport error

Nothing in it touches the network, which is also its limit: **the fixtures keep parsing long after the site has stopped looking like them**. So a [weekly workflow](.github/workflows/upstream.yml) does two things the offline suite cannot:

- `tests/live.sh` asks wooordhunt itself the same questions and checks the shape of the answer rather than its wording
- `tests/refresh.sh fresh` re-downloads every page `routes` names, and the whole offline suite runs **against the fresh copy**. A golden diff there is the site's markup having moved under the saved pages — the failure the offline suite can never produce on its own. The refreshed set is uploaded as a run artifact, so re-recording is a download and a commit

Byte-identical HTML is deliberately not the bar — only the parsed output decides pass or fail, or an ad slot would turn the run red every week. Whether the HTML moved anyway is reported in the run summary

`nix flake check` runs the offline suite plus the packaged wrapper parsing a real page through the real `curl`, every setting reaching the script, and the Home Manager module evaluated against option stubs

## Layout

```
rofi-wooordhunt.sh   the launcher: the only thing on PATH, starts rofi with the modi
wooordhunt-modi.sh   the modi: fetch, parse, emit the rofi protocol
nix/                 package.nix, module.nix, module-test.nix
tests/               run.sh, live.sh, refresh.sh, the saved pages and the golden output
docs/                the screenshots
install.sh           for systems without Nix
```
