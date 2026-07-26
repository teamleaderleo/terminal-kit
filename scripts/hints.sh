#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/hints"
INDEX_FILE="$STATE_DIR/hint-index"
HINTS_FILE="$ROOT/config/hints.txt"
STATUS_KEY="terminal-kit-hint"

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

state_value() {
  local value="on"
  if [[ -r "$STATE_FILE" ]]; then
    value="$(tr -d '[:space:]' < "$STATE_FILE")"
  fi
  case "$value" in
    on|off) printf '%s\n' "$value" ;;
    *) printf 'on\n' ;;
  esac
}

write_state() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" > "$STATE_FILE"
}

load_hints() {
  HINTS=()
  local line
  [[ -r "$HINTS_FILE" ]] || fail "hint catalogue missing at $HINTS_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] && HINTS[${#HINTS[@]}]="$line"
  done < "$HINTS_FILE"
  (( ${#HINTS[@]} > 0 )) || fail "hint catalogue is empty"
}

cmux_ready() {
  command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1
}

target_args=()
if [[ -n "${CMUX_WORKSPACE_ID:-}" ]]; then
  target_args=(--workspace "$CMUX_WORKSPACE_ID")
fi

clear_hint() {
  cmux_ready || return 0
  cmux clear-status "$STATUS_KEY" "${target_args[@]}" >/dev/null 2>&1 || true
}

show_next_hint() {
  local index=0 next hint
  load_hints
  if [[ -r "$INDEX_FILE" ]]; then
    index="$(tr -d '[:space:]' < "$INDEX_FILE")"
  fi
  [[ "$index" =~ ^[0-9]+$ ]] || index=0
  next=$(( (index % ${#HINTS[@]}) + 1 ))
  hint="${HINTS[$((next - 1))]}"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$next" > "$INDEX_FILE"

  cmux_ready || fail "cmux is not running"
  if ! cmux set-status "$STATUS_KEY" "$hint" \
    "${target_args[@]}" --priority 1 >/dev/null 2>&1; then
    fail "this cmux build does not support sidebar status hints"
  fi
  printf 'terminal-kit: sidebar hint %s\n' "$hint"
}

list_hints() {
  local i
  load_hints
  printf 'terminal-kit keys and commands:\n'
  for ((i = 0; i < ${#HINTS[@]}; i++)); do
    printf '%2d  %s\n' "$((i + 1))" "${HINTS[$i]}"
  done
}

usage() {
  cat <<'HELP'
Usage: terminal-kit hints <command>

  current       Show whether fresh-shell hints are enabled
  on            Enable hints for new terminal surfaces
  off           Disable hints and clear the current one
  next|show     Show the next hint in the current workspace
  clear         Remove the current workspace hint
  list          Print the full compact key and command cheat sheet

A fresh cmux terminal shows one low-priority hint in its sidebar row. The first
command clears it. Opening another terminal surface advances to the next hint.
HELP
}

command_name="${1:-current}"
shift || true

case "$command_name" in
  current|status)
    printf 'terminal-kit: fresh-shell sidebar hints %s\n' "$(state_value)"
    ;;
  on)
    write_state on
    printf 'terminal-kit: fresh-shell sidebar hints enabled\n'
    if cmux_ready; then
      show_next_hint
    fi
    ;;
  off)
    write_state off
    clear_hint
    printf 'terminal-kit: fresh-shell sidebar hints disabled\n'
    ;;
  next|show)
    show_next_hint
    ;;
  clear)
    clear_hint
    printf 'terminal-kit: cleared the current sidebar hint\n'
    ;;
  list|keys)
    list_hints
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown hints command: $command_name"
    ;;
esac
