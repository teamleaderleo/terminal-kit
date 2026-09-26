#!/usr/bin/env bash
set -euo pipefail
# bash 3.2 (macOS /bin/bash) ignores set -e for a failing [[ ]]; assert explicitly.
fail_at() { printf '%s: assertion failed at line %s\n' "${0##*/}" "$1" >&2; exit 1; }

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

[[ "$(jq -r '.shortcuts.bindings.newSurface' "$cmux")" == 'cmd+t' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.closeTab' "$cmux")" == 'cmd+w' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.reopenClosedBrowserPanel' "$cmux")" == 'cmd+shift+t' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.nextSurface' "$cmux")" == 'ctrl+tab' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.prevSurface' "$cmux")" == 'ctrl+shift+tab' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.browserBack' "$cmux")" == 'cmd+[' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.browserForward' "$cmux")" == 'cmd+]' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.focusBrowserAddressBar' "$cmux")" == 'cmd+l' ]] || fail_at $LINENO
[[ "$(jq -r '.shortcuts.bindings.find' "$cmux")" == 'cmd+f' ]] || fail_at $LINENO
[[ "$(jq -r '.fileExplorer.doubleClickAction' "$cmux")" == 'preview' ]] || fail_at $LINENO

# Selecting never writes the clipboard, and Cmd+A/C/X/Z keep their terminal
# meanings instead of sending private sequences into whatever program is running.
grep -Fxq 'copy-on-select = false' "$ghostty"
[[ "$(jq -r '.terminal.copyOnSelect' "$cmux")" == false ]] || fail_at $LINENO
if grep -Eq '^keybind *= *(cmd|super)\+(shift\+)?[acxz]=(csi|text|esc):' "$ghostty"; then
  printf 'terminal-kit: Ghostty must not send Cmd+A/C/X/Z into the running program\n' >&2
  exit 1
fi
if grep -q 'pbcopy' "$ROOT/config/tmux/tmux.conf"; then
  printf 'terminal-kit: tmux copies must reach the clipboard once, through set-clipboard\n' >&2
  exit 1
fi

# Karabiner adds Cmd-Shift-]/[ as the browser-style alias for Ctrl-(Shift-)Tab.
[[ "$(jq -c '[.rules[0].manipulators[] | [.from.key_code, (.from.modifiers.mandatory | join("+")), (.to[0].key_code), (.to[0].modifiers | join("+"))]]' "$karabiner")" == '[["close_bracket","command+shift","tab","left_control"],["open_bracket","command+shift","tab","left_control+left_shift"]]' ]] || fail_at $LINENO

printf 'terminal-kit familiar controls tests passed\n'
