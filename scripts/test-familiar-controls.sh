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

# Selecting never writes the clipboard, and Cmd+A/C/X/Z keep their terminal
# meanings instead of sending private sequences into whatever program is running.
grep -Fxq 'copy-on-select = false' "$ghostty"
[[ "$(jq -r '.terminal.copyOnSelect' "$cmux")" == false ]]
if grep -Eq '^keybind *= *(cmd|super)\+(shift\+)?[acxz]=(csi|text|esc):' "$ghostty"; then
  printf 'terminal-kit: Ghostty must not send Cmd+A/C/X/Z into the running program\n' >&2
  exit 1
fi
if grep -q 'pbcopy' "$ROOT/config/tmux/tmux.conf"; then
  printf 'terminal-kit: tmux copies must reach the clipboard once, through set-clipboard\n' >&2
  exit 1
fi

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
