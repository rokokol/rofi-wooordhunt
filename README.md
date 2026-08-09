<div align="center">

# rofi-wooordhunt

**Wooordhunt rofi parser** 🤓

![rofi](https://img.shields.io/badge/rofi-script--modi-F4A100?style=flat)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/rofi-wooordhunt/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/rofi-wooordhunt/actions/workflows/build.yml)

[Русский](README.ru.md)

</div>

Type a word, get the translation, press Enter, it is on your clipboard. **Both directions in one field** — [wooordhunt.ru](https://wooordhunt.ru) decides which one you meant, so there is no mode to switch and no prefix to remember

Reaching for a browser tab costs a window, a page load and a way back. This costs one key

Came over from my rice, **[rokokol/huix](https://github.com/rokokol/huix)**

```sh
# try it on the running session without installing anything
nix run github:rokokol/rofi-wooordhunt
```

## What you get back

**English in** — the transcriptions in the header, one per part of speech when the spelling covers several words, and the meanings as rows:

```
🤓  transfer
    🇺🇸: |trænsˈfɜːr| (глагол), |ˈtrænsfɜːr| (существительное) // 🇬🇧: …
    передача
    перевод
    трансфер
```

**Russian in** — the English words, each with its own transcription, its gloss list, and the site's explanation of when to pick this one over its synonyms:

```
🤓  риск
    🇷🇺: риск （´ω｀♡%）
    risk |rɪsk| — риск, опасность, вероятность убытков
       Основное и самое общее слово для обозначения "риска"…
    jeopardy |ˈdʒepərdɪ| — опасность, риск, угроза
       Более формальный синоним слова "risk" или "danger"…
```

That explanation is what makes the Russian direction worth having: a list of six synonyms says nothing about which one a native speaker would reach for, and this one does. The indented lines are **non-selectable** — arrow keys skip them, so the explanation reads as a note under the word rather than as nine more things to choose from

Enter copies the entry. On a word with an explanation it copies the **word**, not the line you were looking at

Multi-word phrases work — `give up`, `эй там`. The space becomes the underscore the site expects

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

That is the whole setup: the package is installed, `SUPER + Y` opens the dictionary, and the mode names itself through the script protocol — **nothing goes into your rofi config**, no `display-dictionary` line to keep in sync

| option | | default |
| --- | --- | --- |
| `prompt` | what rofi shows as the mode name | `🤓` |
| `modeName` | what the mode is called in `rofi -show` | `dictionary` |
| `copyCommand` | fed the picked entry on stdin | `wl-copy` |
| `wrapWidth` / `headWidth` | where the lines wrap; widen both for a wider window | `54` / `58` |
| `timeout` | seconds a request may take | `5` |
| `hyprland.modifier` / `hyprland.key` | the binding | `SUPER` / `Y` |

Spell the modifier out rather than using `$mainMod` — these lines are emitted before your own config is sourced, so a variable defined there does not exist yet. Set `hyprland.settings` to `{ }` to bind it yourself: `programs.rofi-wooordhunt.command` is the invocation, read-only, so a bind written by hand still follows `modeName`

Not on Hyprland? `hyprland.enable = false`, and bind `command` wherever your compositor keeps its keys

### Any other distribution

```sh
git clone https://github.com/rokokol/rofi-wooordhunt
cd rofi-wooordhunt
sudo ./install.sh          # PREFIX=~/.local ./install.sh for a user install
```

Nothing is built: the script is copied to `$PREFIX/share/rofi-wooordhunt` and symlinked into `$PREFIX/bin`

Needs `bash`, `curl`, [`pup`](https://github.com/ericchiang/pup), `jq`, `awk`, `sed`, `grep`, `fold`, `xargs`, and a clipboard tool — `wl-copy` by default, `ROFI_WOOORDHUNT_COPY="xclip -selection clipboard"` on X11

Then bind it yourself:

```conf
bind = SUPER, Y, exec, rofi -show dictionary -modi "dictionary:rofi-wooordhunt"
```

## Settings

Every Home Manager option above is an environment variable underneath, so the same knobs work without Nix:

| | |
| --- | --- |
| `ROFI_WOOORDHUNT_PROMPT` | the mode name rofi shows |
| `ROFI_WOOORDHUNT_COPY` | the clipboard command |
| `ROFI_WOOORDHUNT_WRAP_WIDTH` | width the indented explanation wraps at |
| `ROFI_WOOORDHUNT_HEAD_WIDTH` | width the word line may reach before its gloss drops below |
| `ROFI_WOOORDHUNT_TIMEOUT` | per-request timeout in seconds |
| `ROFI_WOOORDHUNT_URL` | the site root, for pointing the modi at a mirror or a fixture tree |
| `ROFI_WOOORDHUNT_LOCALE` | the locale the wrapping counts characters in; unset, the modi takes the first UTF-8 locale the machine actually answers to |

The wrapping is ours because **rofi rows are single-line**: text that does not fit is truncated with `…`, never wrapped, so a long explanation has to be broken into rows by hand. That makes both widths a function of your window width — the defaults are for 720px

`rofi-wooordhunt --help` prints the same list. Inside rofi it does not: `ROFI_RETV` is always set there, so `--help` typed into the field is a query like anything else

## How it works

There is no API. The modi fetches the page and reads it with `pup` and `jq`, which is enough because the markup is regular — but the site has **four different shapes** for what is nominally the same answer, and the parser walks them in order:

| the page has | is | shows as |
| --- | --- | --- |
| `section.sub_entry` | the Russian direction: synonym groups, each with a gloss list and an explanation | word + transcription, explanation indented below |
| `.t_inline_en` | the English direction, meanings on one line | one row per meaning |
| `.tr > span` | the English direction, one meaning per span | one row per meaning, the span markup collapsed by hand so `<i>(чрезмерно)</i> подчёркивать` stays one meaning |
| `.light_tr` | a phrase page | the translation as a single row |

Transcriptions live in a different block than the meanings (`.trans_sound`), and the Russian direction carries none at all — so for a Russian query the modi fetches the word page of **every** English result, in parallel, purely for the transcription. A word whose page does not answer simply appears without one

Homographs are why that block is walked rather than grepped: `transfer` is two words with two pronunciations sharing one page, and a `grep` for the first `.transcription` would confidently show you the wrong one

## Tests

```sh
tests/run.sh              # 18 checks, no network
tests/run.sh --update     # re-record the golden output after a deliberate change
tests/live.sh             # the same questions, asked of the real site
```

`tests/run.sh` puts a stub `curl` on PATH that serves saved pages from `tests/fixtures` according to `tests/fixtures/routes`, and diffs the rofi protocol the modi emits against `tests/golden` — so a change in how an answer is assembled shows up as a diff. Two reserved slugs stand in for the failures a saved page cannot express, a timeout and a transport error

Nothing in it touches the network, which is also its limit: **the fixtures keep parsing long after the site has stopped looking like them**. That is what `tests/live.sh` is for — it asks wooordhunt itself the same questions and checks the shape of the answer rather than its wording. A [weekly workflow](.github/workflows/upstream.yml) runs it, so a redesign upstream surfaces as a red run instead of as an empty rofi window

`nix flake check` runs the offline suite plus the packaged wrapper parsing a real page through the real `curl`, every setting reaching the script, and the Home Manager module evaluated against option stubs

## Layout

```
rofi-wooordhunt.sh   the modi: fetch, parse, emit the rofi protocol
nix/                 package.nix, module.nix, module-test.nix
tests/               run.sh, live.sh, the saved pages and the golden output
install.sh           for systems without Nix
```

## License

MIT
