#!/bin/bash

te_json_is_valid() {
  local json="${1:-}"

  [[ -n "$json" && -n "${JQ_BIN:-}" ]] || return 1
  printf '%s\n' "$json" | "$JQ_BIN" -e '.streams | type == "array"' >/dev/null 2>&1
}

te_first_stream_json() {
  local json="${1:-}"
  local codec_type="${2:-}"

  [[ -n "$json" && -n "$codec_type" && -n "${JQ_BIN:-}" ]] || return 0
  printf '%s\n' "$json" | "$JQ_BIN" -c --arg codec_type "$codec_type" \
    '[.streams[]? | select(.codec_type == $codec_type)][0] // empty' 2>/dev/null
}

te_json_value() {
  local json="${1:-}"
  local filter="${2:-}"

  [[ -n "$json" && -n "$filter" && -n "${JQ_BIN:-}" ]] || return 0
  printf '%s\n' "$json" | "$JQ_BIN" -r \
    "$filter | if . == null then empty else . end" 2>/dev/null | head -n1
}

te_stream_count() {
  local json="${1:-}"
  local codec_type="${2:-}"

  [[ -n "$json" && -n "$codec_type" && -n "${JQ_BIN:-}" ]] || {
    printf '0\n'
    return
  }
  printf '%s\n' "$json" | "$JQ_BIN" -r --arg codec_type "$codec_type" \
    '[.streams[]? | select(.codec_type == $codec_type)] | length' 2>/dev/null
}

te_language_tags() {
  local json="${1:-}"
  local codec_type="${2:-}"

  [[ -n "$json" && -n "$codec_type" && -n "${JQ_BIN:-}" ]] || return 0
  printf '%s\n' "$json" | "$JQ_BIN" -r --arg codec_type "$codec_type" '
    [.streams[]? | select(.codec_type == $codec_type) |
      "stream \(.index // "?"): \(.tags.language // "not tagged")"] as $tags |
    if ($tags | length) == 0 then
      "no \($codec_type) streams"
    else
      $tags | join("; ")
    end
  ' 2>/dev/null
}

te_rate_to_decimal() {
  local raw_rate="${1:-}"

  awk -v rate="$raw_rate" 'BEGIN {
    count = split(rate, parts, "/")
    if (count == 2 && parts[1] ~ /^[0-9.]+$/ && parts[2] ~ /^[0-9.]+$/ && parts[2] != 0) {
      printf "%.2f", parts[1] / parts[2]
    } else if (rate ~ /^[0-9]+([.][0-9]+)?$/) {
      printf "%.2f", rate
    }
  }'
}
