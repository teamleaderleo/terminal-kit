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

validate_json() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq empty "$file" >/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$file" >/dev/null <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    json.load(handle)
PY
  else
    return 2
  fi
}

check_json() {
  local file="$1"
  if [[ ! -r "$file" ]]; then
    return 0
  fi

  if validate_json "$file"; then
    printf 'OK   JSON parses cleanly       %s\n' "$file"
  else
    local status=$?
    if (( status == 2 )); then
      printf 'MISS JSON parser for %s (install jq)\n' "$file"
    else
      printf 'BAD  invalid JSON              %s\n' "$file"
    fi
    failures=$((failures + 1))
  fi
}

json_value() {
  local file="$1"
  local jq_path="$2"
  local plist_path="$3"

  if command -v jq >/dev/null 2>&1; then
    jq -r "$jq_path // empty" "$file" 2>/dev/null || true
  elif command -v plutil >/dev/null 2>&1; then
    plutil -extract "$plist_path" raw "$file" 2>/dev/null || true
  fi
}

check_file "$HOME/.config/ghostty/config"
check_file "$HOME/.config/terminal-kit/glass.ghostty"
check_file "$HOME/.config/cmux/cmux.json"
check_file "$HOME/.config/cmux/dock.json"
check_file "$HOME/.tmux.conf"
check_file "$HOME/.zshenv"
check_file "$HOME/.zshrc"

# Standard macOS commands should never disappear from PATH.
check_command uname
check_command awk
check_command grep
check_command mv
check_command tty
check_command zsh
check_command tmux
check_command fzf
check_command atuin
check_command zoxide
check_command eza
check_command bat
check_command grc
check_command delta
check_command starship
check_command yazi
check_command lazygit
check_command btop
check_command rg
check_command fd
check_command jq
check_command hyperfine
check_command cmux

if command -v zsh >/dev/null 2>&1; then
  zsh -n \
    "$ROOT/config/zsh/env.zsh" \
    "$ROOT/config/zsh/init.zsh" \
    "$ROOT/config/zsh/terminal.zsh" \
    "$ROOT/config/zsh/tools.zsh" \
    "$ROOT/config/zsh/hints.zsh" \
    "$ROOT/config/zsh/highlight.zsh"
  printf 'OK   Zsh settings parse cleanly\n'
fi

if [[ -r "$HOME/.config/terminal-kit/hints" ]]; then
  hints_state="$(tr -d '[:space:]' < "$HOME/.config/terminal-kit/hints")"
  printf 'OK   fresh-shell hints         %s\n' "$hints_state"
fi

if settings="$(python3 "$ROOT/scripts/settings.py" 2>&1)"; then
  while IFS= read -r line; do
    printf 'OK   %s\n' "$line"
  done <<< "$settings"
else
  printf 'BAD  settings                  %s\n' "$settings"
  failures=$((failures + 1))
fi

check_json "$ROOT/config/cmux/cmux.json.example"
check_json "$ROOT/config/cmux/dock.json.example"

if [[ -r "$HOME/.config/cmux/cmux.json" ]]; then
  check_json "$HOME/.config/cmux/cmux.json"
  git_watch="$(json_value "$HOME/.config/cmux/cmux.json" '.sidebar.watchGitStatus' 'sidebar.watchGitStatus')"
  case "$git_watch" in
    false|0) printf 'OK   hidden Git watcher        off\n' ;;
    true|1) printf 'WARN hidden Git watcher        on\n' ;;
  esac
fi

if command -v cmux >/dev/null 2>&1; then
  cmux config doctor >/dev/null 2>&1 && printf 'OK   cmux config passes its doctor\n' || true
fi

if (( failures > 0 )); then
  die "$failures required file(s) missing or invalid; run terminal-kit install"
fi

log "doctor finished"
