#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

copy_text() {
  local label="$1"
  local text="$2"
  command -v pbcopy >/dev/null 2>&1 || fail "pbcopy is unavailable"
  printf '%s' "$text" | pbcopy
  printf 'terminal-kit: copied %s\n' "$label"
}

copy_path() {
  copy_text "current path" "$(pwd -P)"
}

copy_project() {
  local root
  root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd -P)"
  copy_text "project path" "$root"
}

copy_command() {
  local command_text="${TERMINAL_KIT_LAST_COMMAND:-}"
  [[ -n "$command_text" ]] || fail "no previous command has been recorded in this shell yet"
  copy_text "last command" "$command_text"
}

copy_screen() {
  [[ -n "${CMUX_SURFACE_ID:-}" ]] || fail "copy screen requires a cmux terminal surface"
  command -v cmux >/dev/null 2>&1 || fail "cmux is unavailable"

  local screen
  screen="$(cmux read-screen --surface "$CMUX_SURFACE_ID")"
  [[ -n "$screen" ]] || fail "the current cmux screen is empty"
  copy_text "visible screen" "$screen"
}

usage() {
  cat <<'HELP'
Usage: terminal-kit copy <command>

  command       Copy the last shell command recorded before this helper ran
  screen        Copy the visible cmux terminal screen
  path          Copy the current working directory
  project       Copy the current Git root, or the working directory outside Git
HELP
}

command_name="${1:-help}"
shift || true

case "$command_name" in
  command|cmd|last)
    [[ $# -eq 0 ]] || fail "copy command takes no arguments"
    copy_command
    ;;
  screen|visible|output)
    [[ $# -eq 0 ]] || fail "copy screen takes no arguments"
    copy_screen
    ;;
  path|cwd)
    [[ $# -eq 0 ]] || fail "copy path takes no arguments"
    copy_path
    ;;
  project|root)
    [[ $# -eq 0 ]] || fail "copy project takes no arguments"
    copy_project
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown copy command: $command_name"
    ;;
esac
