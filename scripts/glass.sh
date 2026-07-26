#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/glass.ghostty"

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

reload_cmux() {
  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
    cmux reload-config >/dev/null 2>&1 || cmux config reload >/dev/null 2>&1 || true
    printf 'terminal-kit: requested a cmux config reload\n'
  fi
  printf 'terminal-kit: fully quit and reopen cmux if the glass material does not change immediately\n'
}

write_preset() {
  local preset="$1"
  local opacity="$2"
  local blur="$3"
  local cells="$4"
  local temporary

  mkdir -p "$STATE_DIR"
  temporary="$STATE_FILE.tmp.$$"
  cat >"$temporary" <<EOF
# terminal-kit glass preset: $preset
# Local machine state; intentionally kept outside the Git repository.
background-opacity = $opacity
background-blur = $blur
background-opacity-cells = $cells
EOF
  mv "$temporary" "$STATE_FILE"
  printf 'terminal-kit: glass preset set to %s\n' "$preset"
  reload_cmux
}

current_preset() {
  if [[ ! -r "$STATE_FILE" ]]; then
    printf 'terminal-kit: no local glass preset yet; run terminal-kit install\n'
    return
  fi

  sed -n 's/^# terminal-kit glass preset: //p' "$STATE_FILE" | head -n 1
  sed -n '/^background-/p' "$STATE_FILE"
}

cycle_preset() {
  local current
  current="$(sed -n 's/^# terminal-kit glass preset: //p' "$STATE_FILE" 2>/dev/null | head -n 1 || true)"
  case "$current" in
    regular) write_preset clear 0.92 macos-glass-clear false ;;
    clear) write_preset immersive 0.88 macos-glass-clear true ;;
    immersive) write_preset opaque 1 false false ;;
    *) write_preset regular 0.90 macos-glass-regular false ;;
  esac
}

usage() {
  cat <<'HELP'
Usage: terminal-kit glass <command>

  current     Show the active local glass preset
  regular     Native regular glass at 90% opacity
  clear       Native clear glass at 92% opacity
  immersive   Clear glass, stronger transparency, and translucent app cells
  opaque      Disable transparency and blur
  cycle       Rotate regular -> clear -> immersive -> opaque
HELP
}

command_name="${1:-current}"
case "$command_name" in
  current|status)
    current_preset
    ;;
  regular)
    write_preset regular 0.90 macos-glass-regular false
    ;;
  clear)
    write_preset clear 0.92 macos-glass-clear false
    ;;
  immersive)
    write_preset immersive 0.88 macos-glass-clear true
    ;;
  opaque|off)
    write_preset opaque 1 false false
    ;;
  cycle)
    cycle_preset
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown glass command: $command_name"
    ;;
esac
