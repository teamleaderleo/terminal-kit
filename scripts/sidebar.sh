#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

cmux_bundle_id() {
  local bundle_id
  bundle_id="$(/usr/bin/osascript -e 'id of application "cmux"' 2>/dev/null || true)"
  [[ -n "$bundle_id" ]] || fail "could not find the installed cmux application"
  printf '%s\n' "$bundle_id"
}

validate_width() {
  local width="$1"
  [[ "$width" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "sidebar width must be a number"
  awk -v width="$width" 'BEGIN { exit !(width >= 120 && width <= 260) }' \
    || fail "sidebar minimum must be between 120 and 260 points"
}

current_width() {
  local bundle_id width
  bundle_id="$(cmux_bundle_id)"
  width="$(/usr/bin/defaults read "$bundle_id" sidebarMinimumWidth 2>/dev/null || true)"
  if [[ -n "$width" ]]; then
    printf 'terminal-kit: sidebar minimum %s points\n' "$width"
  else
    printf 'terminal-kit: sidebar minimum 240 points (cmux default)\n'
  fi
}

set_width() {
  local name="$1"
  local width="$2"
  local bundle_id
  validate_width "$width"
  bundle_id="$(cmux_bundle_id)"
  /usr/bin/defaults write "$bundle_id" sidebarMinimumWidth -float "$width"
  printf 'terminal-kit: sidebar preset %s (%s-point minimum)\n' "$name" "$width"
  printf 'terminal-kit: fully quit and reopen cmux, then drag the sidebar divider left\n'
}

reset_width() {
  local bundle_id
  bundle_id="$(cmux_bundle_id)"
  /usr/bin/defaults delete "$bundle_id" sidebarMinimumWidth >/dev/null 2>&1 || true
  printf 'terminal-kit: restored cmux sidebar minimum to its 240-point default\n'
  printf 'terminal-kit: fully quit and reopen cmux for the change to take effect\n'
}

usage() {
  cat <<'HELP'
Usage: terminal-kit sidebar <command>

  current       Show the configured minimum width
  compact       Allow the left workspace sidebar to shrink to 180 points
  tiny          Allow it to shrink to 140 points
  normal        Restore the 240-point cmux default
  set <points>  Set a custom minimum from 120 through 260
  reset         Remove the override and use cmux's default

The setting changes the lower resize limit; drag the sidebar divider after
restarting cmux to choose the actual width.
HELP
}

command_name="${1:-current}"
shift || true

case "$command_name" in
  current|status)
    current_width
    ;;
  compact)
    set_width compact 180
    ;;
  tiny)
    set_width tiny 140
    ;;
  normal)
    set_width normal 240
    ;;
  set)
    [[ $# -eq 1 ]] || fail "sidebar set expects one numeric width"
    set_width custom "$1"
    ;;
  reset)
    reset_width
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown sidebar command: $command_name"
    ;;
esac
