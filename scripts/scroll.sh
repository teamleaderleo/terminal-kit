#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/scroll-speed"
CMUX_CONFIG="$HOME/.config/cmux/cmux.json"

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

validate_speed() {
  local speed="$1"
  [[ "$speed" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "scroll speed must be a positive number"
  awk -v speed="$speed" 'BEGIN { exit !(speed >= 0.25 && speed <= 4) }' \
    || fail "scroll speed must be between 0.25 and 4"
}

reload_cmux() {
  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
    cmux reload-config >/dev/null 2>&1 || cmux config reload >/dev/null 2>&1 || true
    printf 'terminal-kit: reloaded cmux\n'
  fi
}

apply_speed() {
  local name="$1"
  local speed="$2"

  validate_speed "$speed"
  [[ -r "$CMUX_CONFIG" ]] || fail "cmux config missing; run terminal-kit install"

  mkdir -p "$STATE_DIR"
  printf '%s\n' "$speed" >"$STATE_FILE"
  /usr/bin/plutil -replace terminal.scrollSpeed -float "$speed" "$CMUX_CONFIG"

  printf 'terminal-kit: scroll preset %s (%sx)\n' "$name" "$speed"
  reload_cmux
}

current_speed() {
  if [[ -r "$STATE_FILE" ]]; then
    printf 'terminal-kit: saved scroll speed %sx\n' "$(tr -d '[:space:]' <"$STATE_FILE")"
  else
    printf 'terminal-kit: no saved scroll speed; the install default is 1.4x\n'
  fi

  if [[ -r "$CMUX_CONFIG" ]]; then
    local configured
    configured="$(/usr/bin/plutil -extract terminal.scrollSpeed raw "$CMUX_CONFIG" 2>/dev/null || true)"
    [[ -n "$configured" ]] && printf 'terminal-kit: cmux scroll speed %sx\n' "$configured"
  fi
}

cycle_speed() {
  local current
  current="$(tr -d '[:space:]' <"$STATE_FILE" 2>/dev/null || true)"
  case "$current" in
    0.9) apply_speed balanced 1.0 ;;
    1|1.0) apply_speed brisk 1.4 ;;
    1.4) apply_speed fast 1.8 ;;
    1.8) apply_speed precise 0.9 ;;
    *) apply_speed brisk 1.4 ;;
  esac
}

usage() {
  cat <<'HELP'
Usage: terminal-kit scroll <command>

  current        Show the saved and active cmux scroll multiplier
  precise        0.9x for close reading and fine positioning
  balanced       1.0x cmux default
  brisk          1.4x, the terminal-kit default for a mouse using Mos
  fast           1.8x for long logs and large scrollback buffers
  set <number>   Set a custom multiplier between 0.25 and 4
  cycle          Rotate precise -> balanced -> brisk -> fast
HELP
}

command_name="${1:-current}"
shift || true

case "$command_name" in
  current|status)
    current_speed
    ;;
  precise)
    apply_speed precise 0.9
    ;;
  balanced|normal)
    apply_speed balanced 1.0
    ;;
  brisk)
    apply_speed brisk 1.4
    ;;
  fast)
    apply_speed fast 1.8
    ;;
  set)
    [[ $# -eq 1 ]] || fail "scroll set expects one numeric multiplier"
    apply_speed custom "$1"
    ;;
  cycle)
    cycle_speed
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown scroll command: $command_name"
    ;;
esac
