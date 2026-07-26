#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/config/zsh/terminal.zsh"
fi

if command -v tmux >/dev/null 2>&1; then
  check_socket="terminal-kit-check-$$"
  tmux -L "$check_socket" -f /dev/null new-session -d -s terminal-kit-check
  if ! tmux -L "$check_socket" source-file "$ROOT/config/tmux/tmux.conf"; then
    tmux -L "$check_socket" kill-server >/dev/null 2>&1 || true
    die "tmux rejected the managed settings"
  fi
  tmux -L "$check_socket" kill-server >/dev/null 2>&1 || true

  if tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
    log "reloaded tmux without closing sessions"
  fi
fi

if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
  cmux reload-config >/dev/null 2>&1 || cmux config reload >/dev/null 2>&1 || true
  log "reloaded cmux"
fi

if [[ "$(uname -s)" == "Darwin" ]] && pgrep -x Ghostty >/dev/null 2>&1; then
  if osascript >/dev/null 2>&1 <<'APPLESCRIPT'
tell application "Ghostty"
  if (count of terminals) > 0 then
    perform action "reload_config" on item 1 of terminals
  end if
end tell
APPLESCRIPT
  then
    log "reloaded Ghostty"
  else
    warn "Ghostty is still open; press Command-Shift-, to reload"
  fi
fi

log "settings applied"