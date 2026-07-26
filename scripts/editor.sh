#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/editor-wrap"
CMUX_CONFIG="$HOME/.config/cmux/cmux.json"

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

reload_cmux() {
  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
    cmux reload-config >/dev/null 2>&1 || cmux config reload >/dev/null 2>&1 || true
    printf 'terminal-kit: reloaded cmux\n'
  fi
}

apply_mode() {
  local mode="$1"
  local wrap_value
  [[ -r "$CMUX_CONFIG" ]] || fail "cmux config missing; run terminal-kit install"

  case "$mode" in
    wrap) wrap_value=true ;;
    wide) wrap_value=false ;;
    *) fail "editor mode must be wrap or wide" ;;
  esac

  mkdir -p "$STATE_DIR"
  printf '%s\n' "$mode" >"$STATE_FILE"
  /usr/bin/plutil -replace fileEditor.wordWrap -bool "$wrap_value" "$CMUX_CONFIG"
  printf 'terminal-kit: cmux editor mode %s\n' "$mode"
  reload_cmux
}

current_mode() {
  local saved="wrap"
  [[ -r "$STATE_FILE" ]] && saved="$(tr -d '[:space:]' <"$STATE_FILE")"
  printf 'terminal-kit: saved editor mode %s\n' "$saved"

  if [[ -r "$CMUX_CONFIG" ]]; then
    local configured
    configured="$(/usr/bin/plutil -extract fileEditor.wordWrap raw "$CMUX_CONFIG" 2>/dev/null || true)"
    case "$configured" in
      true|1) printf 'terminal-kit: cmux editor wraps long lines\n' ;;
      false|0) printf 'terminal-kit: cmux editor scrolls long lines horizontally\n' ;;
    esac
  fi
}

toggle_mode() {
  local current="wrap"
  [[ -r "$STATE_FILE" ]] && current="$(tr -d '[:space:]' <"$STATE_FILE")"
  if [[ "$current" == "wide" ]]; then
    apply_mode wrap
  else
    apply_mode wide
  fi
}

usage() {
  cat <<'HELP'
Usage: terminal-kit editor <command>

  current  Show the saved and active editor mode
  wrap     Wrap long lines at the right edge
  wide     Keep long lines on one row and enable horizontal scrolling
  toggle   Switch between wrap and wide

This controls cmux's built-in plain-text editor, not ordinary terminal output.
Use `wide FILE` or `COMMAND | wide` for horizontally scrollable terminal output.
HELP
}

command_name="${1:-current}"
shift || true

case "$command_name" in
  current|status)
    current_mode
    ;;
  wrap)
    apply_mode wrap
    ;;
  wide|nowrap)
    apply_mode wide
    ;;
  toggle)
    toggle_mode
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown editor command: $command_name"
    ;;
esac
