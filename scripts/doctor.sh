#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

failures=0

check_file() {
  local file="$1"
  if [[ -r "$file" ]]; then
    printf 'OK   %s\n' "$file"
  else
    printf 'MISS %s\n' "$file"
    failures=$((failures + 1))
  fi
}

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'OK   %-24s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf 'MISS %s\n' "$command_name"
  fi
}

check_file "$HOME/.config/ghostty/config"
check_file "$HOME/.config/cmux/cmux.json"
check_file "$HOME/.tmux.conf"
check_file "$HOME/.zshrc"
check_file "$ROOT/config/ghostty/config"
check_file "$ROOT/config/ghostty/appearance"
check_file "$ROOT/config/cmux/cmux.json.example"
check_file "$ROOT/config/tmux/tmux.conf"
check_file "$ROOT/config/zsh/init.zsh"
check_file "$ROOT/config/zsh/terminal.zsh"

check_command zsh
check_command tmux
check_command fzf
check_command atuin
check_command zoxide
check_command eza
check_command bat
check_command grc
check_command delta
check_command ghostty
check_command cmux

if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/config/zsh/init.zsh"
  zsh -n "$ROOT/config/zsh/terminal.zsh"
  printf 'OK   Zsh settings parse cleanly\n'
fi

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$ROOT/config/cmux/cmux.json.example" >/dev/null
  printf 'OK   managed cmux JSON parses cleanly\n'
fi

if command -v cmux >/dev/null 2>&1; then
  cmux config doctor >/dev/null 2>&1 && printf 'OK   cmux config passes its doctor\n' || true
fi

if (( failures > 0 )); then
  die "$failures required file(s) missing; run terminal-kit install"
fi

log "doctor finished"
