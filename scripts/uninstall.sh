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
remove_managed_block "$HOME/.zshrc" "zsh"

if [[ -L "$HOME/.local/bin/terminal-kit" ]]; then
  rm "$HOME/.local/bin/terminal-kit"
fi

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 || true
fi

log "removed managed include blocks"
log "left the repository and cmux file in place"
log "backups: $BACKUP_DIR"
