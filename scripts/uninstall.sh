#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

BACKUP_DIR="$HOME/.config/terminal-kit-backups/$(date +%Y%m%d-%H%M%S)-uninstall"
export BACKUP_DIR
mkdir -p "$BACKUP_DIR"

remove_managed_block "$HOME/.config/ghostty/config" "ghostty"
remove_managed_block "$HOME/Library/Application Support/com.mitchellh.ghostty/config" "ghostty"
remove_managed_block "$HOME/.tmux.conf" "tmux"
remove_managed_block "$HOME/.zshenv" "environment"
remove_managed_block "$HOME/.zshrc" "zsh"

if [[ -L "$HOME/.local/bin/terminal-kit" ]]; then
  rm "$HOME/.local/bin/terminal-kit"
fi

remove_retired_state

if command -v jq >/dev/null 2>&1; then
  /bin/bash "$ROOT/scripts/karabiner.sh" remove --quiet || warn "could not remove the Karabiner rule"
fi

if [[ -z "${TERMINAL_KIT_NO_RELOAD:-}" ]] && command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 || true
fi

log "removed the managed blocks, the terminal-kit command, and the Karabiner rule"
log "left in place: this repository, ~/.config/cmux/cmux.json and dock.json,"
log "  ~/.config/terminal-kit (settings), task worktrees and receipts under"
log "  ~/.local/share/terminal-kit and ~/.local/state/terminal-kit, and backups"
if [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
  log "backups: $BACKUP_DIR"
else
  rmdir "$BACKUP_DIR"
fi
