#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/prompt"

mkdir -p "$STATE_DIR"

current_mode() {
  local mode="minimal"
  if [[ -r "$STATE_FILE" ]]; then
    mode="$(tr -d '[:space:]' < "$STATE_FILE")"
  fi
  case "$mode" in
    on|enable) printf 'minimal\n' ;;
    minimal|detailed|off) printf '%s\n' "$mode" ;;
    *) printf 'minimal\n' ;;
  esac
}

set_mode() {
  printf '%s\n' "$1" > "$STATE_FILE"
  printf 'terminal-kit: prompt mode %s; run exec zsh to apply it\n' "$1"
}

case "${1:-status}" in
  on|enable|minimal|calm)
    set_mode minimal
    ;;
  detailed|git|full)
    set_mode detailed
    ;;
  off|disable)
    set_mode off
    ;;
  status|current)
    printf 'terminal-kit: prompt mode %s\n' "$(current_mode)"
    ;;
  *)
    printf 'Usage: terminal-kit prompt minimal|detailed|off|status\n' >&2
    exit 2
    ;;
esac
