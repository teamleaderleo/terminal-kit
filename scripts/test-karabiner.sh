#!/usr/bin/env bash
set -euo pipefail
trap 'printf "terminal-kit Karabiner test failed at line %s\n" "$LINENO" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null 2>&1 || {
  printf 'terminal-kit Karabiner test: jq is required\n' >&2
  exit 1
}

jq empty "$ROOT/config/karabiner/terminal-kit.json"
jq empty "$ROOT/config/cmux/cmux.json.example"
[[ "$(jq -r '.shortcuts.bindings.nextSurface' "$ROOT/config/cmux/cmux.json.example")" == 'ctrl+tab' ]]
[[ "$(jq -r '.shortcuts.bindings.prevSurface' "$ROOT/config/cmux/cmux.json.example")" == 'ctrl+shift+tab' ]]
grep -Fq '⌘Tab / ⌘⇧Tab Next / previous surface' "$ROOT/config/hints.txt"
[[ "$(jq -r '.rules[0].description' "$ROOT/config/karabiner/terminal-kit.json")" == 'terminal-kit: browser-style cmux surface switching' ]]
[[ "$(jq -r '.rules[0].manipulators | length' "$ROOT/config/karabiner/terminal-kit.json")" == 4 ]]
[[ "$(jq -r '.rules[0].manipulators[0].to[0].modifiers | join(",")' "$ROOT/config/karabiner/terminal-kit.json")" == left_control ]]
[[ "$(jq -r '.rules[0].manipulators[1].to[0].modifiers | join(",")' "$ROOT/config/karabiner/terminal-kit.json")" == left_control,left_shift ]]
[[ "$(jq -r '.rules[0].manipulators[2].to[0].modifiers | join(",")' "$ROOT/config/karabiner/terminal-kit.json")" == left_command ]]

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
home="$scratch/home"
live="$home/.config/karabiner/karabiner.json"
asset="$home/.config/karabiner/assets/complex_modifications/terminal-kit.json"
snapshot="$scratch/portable.json"
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
export TERMINAL_KIT_KARABINER_SNAPSHOT="$snapshot"

"$ROOT/bin/terminal-kit" karabiner apply >/dev/null
jq empty "$live"
cmp -s "$ROOT/config/karabiner/terminal-kit.json" "$asset"
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "terminal-kit: browser-style cmux surface switching")) | length' "$live")" == 1 ]]
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "local keep-me rule")) | length' "$live")" == 1 ]]
[[ "$(jq -r '.profiles[0].devices[0].identifiers.vendor_id' "$live")" == 456 ]]

before="$(shasum "$live" "$asset")"
"$ROOT/bin/terminal-kit" karabiner apply >/dev/null
after="$(shasum "$live" "$asset")"
[[ "$before" == "$after" ]]

"$ROOT/bin/terminal-kit" karabiner export >/dev/null
jq empty "$snapshot"
[[ "$(jq -r '.sourceProfile' "$snapshot")" == 'Default profile' ]]
[[ "$(jq -r '.profile.simple_modifications[0].from.key_code' "$snapshot")" == caps_lock ]]
[[ "$(jq -r '.profile.complex_modifications.rules | map(select(.description == "local keep-me rule")) | length' "$snapshot")" == 1 ]]
[[ "$(jq -r '.profile.complex_modifications.rules | map(select(.description == "terminal-kit: browser-style cmux surface switching")) | length' "$snapshot")" == 0 ]]
if jq -e '.profile.devices' "$snapshot" >/dev/null 2>&1; then
  printf 'terminal-kit Karabiner test: portable snapshot leaked devices\n' >&2
  exit 1
fi

# Simulate local drift after export. Sync should restore snapshot-owned mappings
# while preserving unrelated local mappings, rules, and device state.
tmp="$(mktemp)"
jq '
  .profiles[0].simple_modifications = [
    {"from":{"key_code":"caps_lock"},"to":[{"key_code":"escape"}]},
    {"from":{"key_code":"left_control"},"to":[{"key_code":"left_command"}]}
  ]
  | .profiles[0].complex_modifications.rules = [
      {"description":"later local rule","manipulators":[]}
    ]
' "$live" > "$tmp"
mv "$tmp" "$live"

"$ROOT/bin/terminal-kit" karabiner sync >/dev/null
[[ "$(jq -r '.profiles[0].simple_modifications[] | select(.from.key_code == "caps_lock") | .to[0].key_code' "$live")" == left_control ]]
[[ "$(jq -r '.profiles[0].simple_modifications[] | select(.from.key_code == "left_control") | .to[0].key_code' "$live")" == left_command ]]
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "local keep-me rule")) | length' "$live")" == 1 ]]
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "later local rule")) | length' "$live")" == 1 ]]
[[ "$(jq -r '.profiles[0].complex_modifications.rules | map(select(.description == "terminal-kit: browser-style cmux surface switching")) | length' "$live")" == 1 ]]
[[ "$(jq -r '.profiles[0].devices[0].identifiers.product_id' "$live")" == 123 ]]

status="$("$ROOT/bin/terminal-kit" karabiner status)"
grep -Fq 'profile:     Default profile' <<< "$status"
grep -Fq 'cmux alias:  true' <<< "$status"

printf 'terminal-kit Karabiner tests passed\n'
