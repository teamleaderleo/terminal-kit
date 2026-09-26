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

  if [[ -z "${TERMINAL_KIT_NO_RELOAD:-}" ]] && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
    log "reloaded tmux without closing sessions"
  fi
fi

python3 "$ROOT/scripts/settings.py" _render

if [[ -z "${TERMINAL_KIT_NO_RELOAD:-}" ]] && command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
  reload_cmux
  if ! cmux config doctor >/dev/null 2>&1; then
    warn "cmux reloaded, but its config doctor reported a problem"
  fi
fi

# Karabiner reloads its config file on change. Only terminal-kit's own rule is
# added or refreshed; the rest of the profile is left alone.
if command -v jq >/dev/null 2>&1 || [[ -e "$HOME/.config/karabiner/karabiner.json" ]]; then
  /bin/bash "$ROOT/scripts/karabiner.sh" apply --quiet
fi

if [[ -z "${TERMINAL_KIT_NO_RELOAD:-}" && "$(uname -s)" == "Darwin" ]] && pgrep -x Ghostty >/dev/null 2>&1; then
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

prune_backups 10
log "settings applied"
