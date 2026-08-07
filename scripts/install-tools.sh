#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew is missing; skipped tmux, fzf, Atuin, and Zsh helper installation."
  warn "Install Homebrew later, then run: terminal-kit tools"
  exit 0
fi

log "installing any missing command-line tools with Homebrew"
# Homebrew may refresh its package metadata before bundle runs. Keep that refresh
# and normal upgrades, while omitting the unrelated list of newly-added casks.
HOMEBREW_NO_UPDATE_REPORT_NEW=1 brew bundle --file "$ROOT/Brewfile"
