#!/usr/bin/env bash

set -euo pipefail

# Everything here is Cyrillic, IPA and emoji, and the wrapping counts characters — under
# a C locale fold and ${#s} count bytes instead and the layout collapses. Which UTF-8
# locale exists is not something to assume: setlocale silently keeps the old one when the
# name is unknown, so ask a two-byte character how long it is and take the first that
# answers 1. Everything downstream is a child process sharing this LC_ALL
# Asked of a child process on purpose: bash keeps its own locale when setlocale rejects a
# name, but still exports the rejected one, so only a child reports what fold will see
utf8_ready() {
  (($(printf 'ä' | wc -m) == 1))
}
[[ -n "${ROFI_WOOORDHUNT_LOCALE:-}" ]] && export LC_ALL="$ROFI_WOOORDHUNT_LOCALE"
if ! utf8_ready; then
  # Nothing to restore if none of them takes: an unknown name leaves glibc in C, which
  # is where we already were
  for loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    export LC_ALL="$loc"
    utf8_ready && break
  done
fi

INPUT="$*"
SENTINEL_NOOP="__wooordhunt_noop__"
BASE_URL="${ROFI_WOOORDHUNT_URL:-https://wooordhunt.ru}"
COPY_CMD="${ROFI_WOOORDHUNT_COPY:-wl-copy}"
PROMPT="${ROFI_WOOORDHUNT_PROMPT:-🤓}"
TIMEOUT="${ROFI_WOOORDHUNT_TIMEOUT:-5}"
# Wrap widths (in characters) for a 720px window: WRAP_WIDTH — for indented hint
# lines, HEAD_MAX — for the "word+gloss" line before it wraps below
WRAP_WIDTH="${ROFI_WOOORDHUNT_WRAP_WIDTH:-54}"
HEAD_MAX="${ROFI_WOOORDHUNT_HEAD_WIDTH:-58}"

usage() {
  cat <<EOF
rofi-wooordhunt — a rofi script-modi translating through wooordhunt.ru

  rofi -show dictionary -modi "dictionary:$(basename "$0")"

Type a word in either direction; Enter copies the highlighted entry. Environment:

  ROFI_WOOORDHUNT_PROMPT       rofi mode name (default: 🤓)
  ROFI_WOOORDHUNT_COPY         clipboard command fed on stdin (default: wl-copy)
  ROFI_WOOORDHUNT_URL          site root (default: https://wooordhunt.ru)
  ROFI_WOOORDHUNT_TIMEOUT      per-request timeout in seconds (default: 5)
  ROFI_WOOORDHUNT_WRAP_WIDTH   wrap width of the indented hint lines (default: 54)
  ROFI_WOOORDHUNT_HEAD_WIDTH   width the word line may reach before the gloss drops below (default: 58)
  ROFI_WOOORDHUNT_LOCALE       locale the wrapping counts characters in (default: the first UTF-8 one that works)
EOF
}

# rofi always exports ROFI_RETV, so --help can only come from a real shell
if [[ -z "${ROFI_RETV:-}" && ("$INPUT" == "--help" || "$INPUT" == "-h") ]]; then
  usage
  exit 0
fi

print_message() {
  printf '\0message\x1f%s\n' "$1"
}

print_entry() {
  local display="$1"
  local copy_value="${2:-$1}"
  printf '%s\0info\x1f%s\n' "$display" "$copy_value"
}

print_fallback_entry() {
  printf '%s\0info\x1f%s\n' "---" "$SENTINEL_NOOP"
}

# Print a long hint under the translation. rofi rows are single-line, so we wrap
# manually and emit one line per item. The lines are non-selectable (skipped during
# navigation) and carry the English word as the copy value, so a stray activation
# still copies something meaningful
print_hint_lines() {
  local text="$1" copy_value="$2" line
  while IFS= read -r line; do
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    printf '   %s\0info\x1f%s\x1fnonselectable\x1ftrue\n' "$line" "$copy_value"
  done < <(printf '%s\n' "$text" | fold -s -w "$WRAP_WIDTH")
}

if [[ -n "${ROFI_INFO:-}" ]]; then
  if [[ "$ROFI_INFO" != "$SENTINEL_NOOP" ]]; then
    # Unquoted on purpose — the setting carries its own flags (e.g. "xclip -selection clipboard")
    # shellcheck disable=SC2086
    printf '%s' "$ROFI_INFO" | $COPY_CMD
  fi
  exit 0
fi

# Naming the mode here keeps the modi self-contained — nothing to declare in rofi's config
printf '\0prompt\x1f%s\n' "$PROMPT"

if [[ -z "$INPUT" ]]; then
  print_message "Wooordhunt ultra parser （´ω｀♡%）"
  exit 0
fi

ORIGINAL_INPUT=$(printf '%s\n' "$INPUT" | xargs)
PARSED_INPUT="${ORIGINAL_INPUT,,}"
# wooordhunt uses underscores for multi-word phrases (e.g. give_up); a bare space
# in the URL breaks curl, so we collapse spaces into "_"
URL_SLUG="${PARSED_INPUT// /_}"

fetch_html() {
  curl -fsSL --max-time "$TIMEOUT" "$1" 2>/dev/null
}

# Parse the pronunciation block of a word page into lines, one per pronounced form:
# "<us-transcription>\t<uk-transcription>\t<part of speech>". Homographs (e.g.
# transfer as a noun and a verb) come as several us/uk blocks with a shared id
# inside <div class="trans_sound">, each preceded by a label like
# "глагол произносится"; we walk the block in order, saving each form and marking it
# with the part-of-speech word from the site itself (the first label token, empty
# for words with a single form)
# Arguments: $1 = HTML
parse_transcriptions() {
  printf '%s' "$1" | pup '.trans_sound json{}' 2>/dev/null | jq -r '
    .[].children
    | reduce .[] as $c ({forms: [], cur: null};
        if (($c.class // "") | startswith("es_div")) then
          (if .cur then .forms += [.cur] else . end)
          | .cur = {us: "", uk: "", pos:
              ([$c.children[]? | select((.class // "") == "es_i") | .text]
               | first // "" | gsub("^\\s+|\\s+$"; "") | split(" ")[0])}
        elif ($c.id // "") == "us_tr_sound" then
          (.cur //= {us: "", uk: "", pos: ""})
          | .cur.us = ([$c.children[]? | select((.class // "") == "transcription") | .text]
                        | first // "" | gsub("^\\s+|\\s+$"; ""))
        elif ($c.id // "") == "uk_tr_sound" then
          (.cur //= {us: "", uk: "", pos: ""})
          | .cur.uk = ([$c.children[]? | select((.class // "") == "transcription") | .text]
                        | first // "" | gsub("^\\s+|\\s+$"; ""))
        else . end)
    | (if .cur then .forms + [.cur] else .forms end)
    | .[] | select((.us | length > 0) or (.uk | length > 0))
    | [.us, .uk, .pos] | @tsv
  ' 2>/dev/null || true
}

# Render the parsed transcription rows for display. With multiple forms (homographs)
# each transcription is marked with its part of speech so pronunciations differ
# rather than silently merging; a single form is shown bare
#   mode=head  -> American, British as a fallback (RU->EN annotations)
#   mode=us|uk -> only this accent (EN->RU header line)
format_transcriptions() {
  local rows="$1" mode="$2" us uk pos val part result="" count
  count=$(printf '%s\n' "$rows" | grep -c . || true)
  while IFS=$'\t' read -r us uk pos; do
    case "$mode" in
      head) val="${us:-$uk}" ;;
      us) val="$us" ;;
      uk) val="$uk" ;;
    esac
    val=$(printf '%s' "$val" | xargs)
    [[ -z "$val" ]] && continue
    part="$val"
    [[ "$count" -gt 1 && -n "$pos" ]] && part="${val} (${pos})"
    [[ -z "$result" ]] && result="$part" || result+=", ${part}"
  done < <(printf '%s\n' "$rows")
  printf '%s' "$result"
}

# US transcription(s) for one English word, e.g. "house" -> |haʊs|, with British as
# a fallback. Annotates RU->EN results that lack it
fetch_transcription() {
  local slug="${1// /_}" html
  html=$(fetch_html "${BASE_URL}/word/${slug}" || true)
  format_transcriptions "$(parse_transcriptions "$html")" head
}

HTML=""
if HTML=$(fetch_html "${BASE_URL}/переводы/${URL_SLUG}"); then
  :
else
  if HTML=$(fetch_html "${BASE_URL}/word/${URL_SLUG}"); then
    :
  else
    last_status=$?
    case "$last_status" in
      22) print_message "Nothing found: ${PARSED_INPUT} (╯°□°）╯︵ ┻━┻" ;;
      28) print_message "Wooordhunt didn't respond in time ٩(ó｡ò۶ ♡)))♬" ;;
      *) print_message "Failed to get a response from Wooordhunt |_・)" ;;
    esac
    print_fallback_entry
    exit 0
  fi
fi

TR_ROWS=$(parse_transcriptions "$HTML")
TRANSCRIPTION_US=$(format_transcriptions "$TR_ROWS" us)
TRANSCRIPTION_UK=$(format_transcriptions "$TR_ROWS" uk)

if [[ -n "$TRANSCRIPTION_US" || -n "$TRANSCRIPTION_UK" ]]; then
  print_message "🇺🇸: ${TRANSCRIPTION_US} // 🇬🇧: ${TRANSCRIPTION_UK}"
# Anything outside printable ASCII means the query was not an English word. A а-я range
# would say the same, but ranges need a collation the C.UTF-8 locale above does not carry
elif [[ "$PARSED_INPUT" == *[^\ -~]* ]]; then
  print_message "🇷🇺: ${ORIGINAL_INPUT} （´ω｀♡%）"
fi

if printf '%s' "$HTML" | grep -q 'class="sub_entry"'; then
  # Each sub_entry is one meaning group: one or several synonym words (e.g.
  # "exam / examination") with a shared "— gloss" list and one explanation. We parse
  # section by section via JSON so words, glosses and meanings don't drift — flat
  # text drifts when a section has several words or no meaning
  SECTIONS=$(printf '%s' "$HTML" | pup 'section.sub_entry json{}' 2>/dev/null | jq -r '
    .[] |
      (.children[]? | select(.tag=="h3")) as $h3 |
      # Most words sit in <a> links, but unlinked phrases (e.g. "baking oven") come
      # as a bare <span>; take both. A word may be the own text of the link (transfer)
      # or nested one level into a <span> (risk -> <a><span>risk</span>), so we fall
      # back to the children text. (Transcriptions live in a separate block and are
      # fetched per-word below, never inside these h3)
      ([$h3.children[]?
         | select(.tag == "a" or .tag == "span")
         | (([.text] + [.children[]?.text]) | map(select(. != null and (. | test("\\S")))) | first // "")
         | select(. != "")
       ] | join(" / ")) as $words |
      (($h3.text // "") | (capture("—\\s*(?<g>.*)")?.g) // "") as $gloss |
      ((.children[]? | select(.tag=="p" and ((.class // "") | test("meaning"))) | .text) // "") as $meaning |
      [$words, $gloss, $meaning] | @tsv
  ' 2>/dev/null || true)

  if [[ -z "$SECTIONS" ]]; then
    print_message "Failed to parse the Wooordhunt response (T＿T)"
    print_fallback_entry
    exit 0
  fi

  trans_key() {
    local s="${1// /_}"
    printf '%s' "${s//[^a-zA-Z0-9_]/_}"
  }

  # Fetch each English word's transcription in parallel (RU->EN pages don't have them)
  TMPD=$(mktemp -d)
  trap 'rm -rf "$TMPD"' EXIT
  while IFS= read -r word; do
    word=$(printf '%s' "$word" | xargs)
    [[ -z "$word" ]] && continue
    (fetch_transcription "$word" >"$TMPD/$(trans_key "$word")" 2>/dev/null || true) &
  done < <(cut -f1 <<<"$SECTIONS" | sed 's@ / @\n@g' | sort -u)
  wait

  while IFS=$'\t' read -r words gloss meaning; do
    [[ -z "$words" ]] && continue
    gloss=$(printf '%s' "$gloss" | xargs)
    meaning=$(printf '%s' "$meaning" | xargs)

    # The first word is what we copy; build head with each word's transcription
    mapfile -t wlist < <(printf '%s\n' "$words" | sed 's@ / @\n@g')
    copy_word=$(printf '%s' "${wlist[0]}" | xargs)
    head=""
    for w in "${wlist[@]}"; do
      w=$(printf '%s' "$w" | xargs)
      [[ -z "$w" ]] && continue
      tr=$(cat "$TMPD/$(trans_key "$w")" 2>/dev/null || true)
      part="$w"
      [[ -n "$tr" ]] && part+=" ${tr}"
      [[ -z "$head" ]] && head="$part" || head+=" / ${part}"
    done

    # Keep short gloss lists on the word line; wrap long ones onto indented lines
    # below so the selectable line doesn't overflow the window
    gloss_below=""
    if [[ -n "$gloss" ]]; then
      if ((${#head} + ${#gloss} + 3 <= HEAD_MAX)); then
        head+=" — ${gloss}"
      else
        gloss_below="$gloss"
      fi
    fi
    print_entry "$head" "$copy_word"
    [[ -n "$gloss_below" ]] && print_hint_lines "$gloss_below" "$copy_word"
    [[ -n "$meaning" ]] && print_hint_lines "$meaning" "$copy_word"
  done < <(printf '%s\n' "$SECTIONS")
  exit 0
fi

MEANINGS_LIST=""
if printf '%s' "$HTML" | grep -q 'class="t_inline_en"'; then
  MEANINGS_LIST=$(printf '%s' "$HTML" | pup '.t_inline_en text{}' 2>/dev/null | xargs)
else
  # One translation per span child. We collapse each span's HTML manually rather
  # than via `text{}`, because a span may wrap an introductory word in its own tag
  # (e.g. "<i>(чрезмерно)</i> подчёркивать"); text{} would emit that as two lines
  # and split one meaning into two items
  TR_SPANS=$(printf '%s' "$HTML" | pup '.tr > span' 2>/dev/null | awk '
    /^<span/ { buf = ""; next }
    /^<\/span>/ {
      gsub(/<[^>]*>/, "", buf)
      gsub(/[[:space:]]+/, " ", buf)
      sub(/^ /, "", buf); sub(/ $/, "", buf)
      if (buf != "") print buf
      next
    }
    { buf = buf " " $0 }
  ' || true)
  if [[ -n "$TR_SPANS" ]]; then
    MEANINGS_LIST="$TR_SPANS"
  elif printf '%s' "$HTML" | grep -q 'class="t_inline"'; then
    MEANINGS_LIST=$(printf '%s' "$HTML" | pup 'p.t_inline:first-of-type text{}' 2>/dev/null | xargs)
  else
    TR_TEXT=$(printf '%s' "$HTML" | pup '.tr text{}' 2>/dev/null | sed -n 's/^[[:space:]]*-[[:space:]]*//p' || true)
    if [[ -n "$TR_TEXT" ]]; then
      MEANINGS_LIST="$TR_TEXT"
    fi
  fi
fi

# Phrase pages (e.g. "эй там") carry the translation in .light_tr rather than in
# one of the structured selectors above
if [[ -z "$MEANINGS_LIST" ]]; then
  MEANINGS_LIST=$(printf '%s' "$HTML" | pup '.light_tr text{}' 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep . || true)
fi

if [[ -z "$MEANINGS_LIST" ]]; then
  print_message "Failed to parse the Wooordhunt response ヽ(；▽；)ノ"
  print_fallback_entry
  exit 0
fi

printf '%s\n' "$MEANINGS_LIST" | sed 's/, /\n/g' | while IFS= read -r piece; do
  piece=$(printf '%s' "$piece" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [[ -z "$piece" ]] && continue
  print_entry "$piece"
done
