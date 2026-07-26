#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/prompt"

mkdir -p "$STATE_DIR"

case "${1:-status}" in
  on|enable)
    printf 'on\n' >"$STATE_FILE"
    printf 'terminal-kit: prompt enabled; run exec zsh to apply it\n'
    ;;
  off|disable)
    printf 'off\n' >"$STATE_FILE"
    printf 'terminal-kit: prompt disabled; run exec zsh to apply it\n'
    ;;
  status|current)
    if [[ -r "$STATE_FILE" ]]; then
      printf 'terminal-kit: prompt %s\n' "$(tr -d '[:space:]' <"$STATE_FILE")"
    else
      printf 'terminal-kit: prompt on (install default)\n'
    fi
    ;;
  *)
    printf 'Usage: terminal-kit prompt on|off|status\n' >&2
    exit 2
    ;;
esac
