#!/usr/bin/env bash
set -euo pipefail
# bash 3.2 (macOS /bin/bash) ignores set -e for a failing [[ ]]; assert explicitly.
fail_at() { printf '%s: assertion failed at line %s\n' "${0##*/}" "$1" >&2; exit 1; }
trap 'printf "terminal-kit Karabiner test failed at line %s\n" "$LINENO" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null 2>&1 || {
  printf 'terminal-kit Karabiner test: jq is required\n' >&2
  exit 1
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
home="$scratch/home"
live="$home/.config/karabiner/karabiner.json"
asset="$home/.config/karabiner/assets/complex_modifications/terminal-kit.json"
mkdir -p "$(dirname "$live")"

cat > "$live" <<'JSON'
{
  "global": {
    "show_in_menu_bar": true
  },
  "profiles": [
    {
      "name": "Default profile",
      "selected": true,
      "simple_modifications": [
        {
          "from": {"key_code": "caps_lock"},
          "to": [{"key_code": "left_control"}]
        }
      ],
      "fn_function_keys": [
        {
          "from": {"key_code": "f1"},
          "to": [{"consumer_key_code": "display_brightness_decrement"}]
        }
      ],
      "complex_modifications": {
        "parameters": {
          "basic.to_if_alone_timeout_milliseconds": 900
        },
        "rules": [
          {
            "description": "local keep-me rule",
            "manipulators": []
          },
          {
            "description": "terminal-kit: browser-style cmux surface switching",
            "manipulators": [{"type": "basic", "from": {"key_code": "tab"}}]
          }
        ]
      },
      "devices": [
        {
          "identifiers": {
            "is_keyboard": true,
            "product_id": 123,
            "vendor_id": 456
          },
          "ignore": false
        }
      ]
    }
  ]
}
JSON

export HOME="$home"
export TERMINAL_KIT_KARABINER_CONFIG="$live"
export TERMINAL_KIT_KARABINER_ASSET="$asset"

"$ROOT/bin/terminal-kit" karabiner apply >/dev/null
jq empty "$live"
cmp -s "$ROOT/config/karabiner/terminal-kit.json" "$asset"
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "terminal-kit: browser-style cmux surface switching")) | length' "$live")" == 1 ]] || fail_at $LINENO
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "local keep-me rule")) | length' "$live")" == 1 ]] || fail_at $LINENO
[[ "$(jq -r '.profiles[0].devices[0].identifiers.vendor_id' "$live")" == 456 ]] || fail_at $LINENO

before="$(shasum "$live" "$asset")"
"$ROOT/bin/terminal-kit" karabiner apply >/dev/null
after="$(shasum "$live" "$asset")"
[[ "$before" == "$after" ]] || fail_at $LINENO

# An older copy of the rule is replaced, not duplicated.
[[ "$(jq -r '.profiles[0].complex_modifications.rules[] | select(.description == "terminal-kit: browser-style cmux surface switching") | .manipulators | map(.from.key_code) | join(",")' "$live")" == close_bracket,open_bracket ]] || fail_at $LINENO

# Later local edits survive a sync.
tmp="$(mktemp)"
jq '.profiles[0].complex_modifications.rules += [{"description":"later local rule","manipulators":[]}]' "$live" > "$tmp"
mv "$tmp" "$live"
"$ROOT/bin/terminal-kit" karabiner sync >/dev/null
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "later local rule")) | length' "$live")" == 1 ]] || fail_at $LINENO
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "terminal-kit: browser-style cmux surface switching")) | length' "$live")" == 1 ]] || fail_at $LINENO
[[ "$(jq -r '.profiles[0].simple_modifications[0].to[0].key_code' "$live")" == left_control ]] || fail_at $LINENO
[[ "$(jq -r '.profiles[0].devices[0].identifiers.product_id' "$live")" == 123 ]] || fail_at $LINENO

status="$("$ROOT/bin/terminal-kit" karabiner status)"
grep -Fq 'profile:     Default profile' <<< "$status"
grep -Fq 'cmux alias:  true' <<< "$status"

"$ROOT/bin/terminal-kit" karabiner remove >/dev/null
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "terminal-kit: browser-style cmux surface switching")) | length' "$live")" == 0 ]] || fail_at $LINENO
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "local keep-me rule")) | length' "$live")" == 1 ]] || fail_at $LINENO
[[ ! -e "$asset" ]] || fail_at $LINENO

printf 'terminal-kit Karabiner tests passed\n'
