#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmux="$ROOT/config/cmux/cmux.json.example"
karabiner="$ROOT/config/karabiner/terminal-kit.json"
ghostty="$ROOT/config/ghostty/config"
zsh="$ROOT/config/zsh/terminal.zsh"

command -v jq >/dev/null 2>&1 || {
  printf 'terminal-kit familiar-controls test: jq is required\n' >&2
  exit 1
}

jq empty "$cmux"
jq empty "$karabiner"

[[ "$(jq -r '.shortcuts.bindings.newSurface' "$cmux")" == 'cmd+t' ]]
[[ "$(jq -r '.shortcuts.bindings.closeTab' "$cmux")" == 'cmd+w' ]]
[[ "$(jq -r '.shortcuts.bindings.reopenClosedBrowserPanel' "$cmux")" == 'cmd+shift+t' ]]
[[ "$(jq -r '.shortcuts.bindings.nextSurface' "$cmux")" == 'ctrl+tab' ]]
[[ "$(jq -r '.shortcuts.bindings.prevSurface' "$cmux")" == 'ctrl+shift+tab' ]]
[[ "$(jq -r '.shortcuts.bindings.browserBack' "$cmux")" == 'cmd+[' ]]
[[ "$(jq -r '.shortcuts.bindings.browserForward' "$cmux")" == 'cmd+]' ]]
[[ "$(jq -r '.shortcuts.bindings.focusBrowserAddressBar' "$cmux")" == 'cmd+l' ]]
[[ "$(jq -r '.shortcuts.bindings.find' "$cmux")" == 'cmd+f' ]]
[[ "$(jq -r '.fileExplorer.doubleClickAction' "$cmux")" == 'preview' ]]

grep -Fxq 'right-click-action = context-menu' "$ghostty"
grep -Fxq 'copy-on-select = clipboard' "$ghostty"
grep -Fxq 'keybind = cmd+v=paste_from_clipboard' "$ghostty"
grep -Fxq 'keybind = cmd+a=csi:25~' "$ghostty"

grep -Fq '_terminal_kit_select_all() {' "$zsh"
grep -Fxq 'zle -N _terminal_kit_select_all' "$zsh"
grep -Fxq "bindkey '\\e[25~' _terminal_kit_select_all" "$zsh"

[[ "$(jq -r '.rules[0].manipulators | length' "$karabiner")" == 6 ]]
[[ "$(jq -r '.rules[0].manipulators[2].from.key_code' "$karabiner")" == close_bracket ]]
[[ "$(jq -r '.rules[0].manipulators[2].from.modifiers.mandatory | join(",")' "$karabiner")" == command,shift ]]
[[ "$(jq -r '.rules[0].manipulators[2].to[0].modifiers | join(",")' "$karabiner")" == left_control ]]
[[ "$(jq -r '.rules[0].manipulators[3].from.key_code' "$karabiner")" == open_bracket ]]
[[ "$(jq -r '.rules[0].manipulators[3].to[0].modifiers | join(",")' "$karabiner")" == left_control,left_shift ]]

grep -Fq '⌘W Close surface' "$ROOT/config/hints.txt"
grep -Fq '⌘⇧T Reopen closed' "$ROOT/config/hints.txt"
grep -Fq 'Right-click Context menu' "$ROOT/config/hints.txt"

printf 'terminal-kit familiar controls tests passed\n'
