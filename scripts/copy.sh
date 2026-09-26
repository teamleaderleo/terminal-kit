#!/usr/bin/env bash
# `tk copy` (and the `clip` shell function): explicit clipboard writes only.
set -euo pipefail

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

copy_text() {
  local label="$1" text="$2"
  command -v pbcopy >/dev/null 2>&1 || fail "pbcopy is unavailable"
  printf '%s' "$text" | pbcopy
  printf 'terminal-kit: copied %s\n' "$label"
}

git_value() {
  git "$@" 2>/dev/null || fail "not in a Git repository with that information"
}

web_url() {
  local remote value
  remote="$(git_value remote get-url origin)" || exit 1
  case "$remote" in
    git@*:*) remote="${remote#git@}"; value="https://${remote%%:*}/${remote#*:}" ;;
    ssh://git@*) value="https://${remote#ssh://git@}" ;;
    *) value="$remote" ;;
  esac
  printf '%s\n' "${value%.git}"
}

usage() {
  cat <<'HELP'
Usage: terminal-kit copy <what>     (clip <what> in the shell)

  command   the last shell command
  screen    the visible cmux terminal screen
  path      the current directory
  project   the Git root, or the current directory outside Git
  branch    the current Git branch
  commit    the current commit SHA
  remote    the origin remote URL
  web       the origin as an https:// browser URL
  FILE      the contents of a file
  TEXT      the text itself
  ... | tk copy   standard input
HELP
}

if (( $# == 0 )); then
  if [[ -t 0 ]]; then
    usage >&2
    exit 2
  fi
  command -v pbcopy >/dev/null 2>&1 || fail "pbcopy is unavailable"
  pbcopy
  printf 'terminal-kit: copied stdin\n'
  exit 0
fi

case "$1" in
  command|cmd|last)
    [[ -n "${TERMINAL_KIT_LAST_COMMAND:-}" ]] || fail "no previous command has been recorded in this shell yet"
    copy_text "last command" "$TERMINAL_KIT_LAST_COMMAND"
    ;;
  screen)
    [[ -n "${CMUX_SURFACE_ID:-}" ]] || fail "copy screen requires a cmux terminal surface"
    command -v cmux >/dev/null 2>&1 || fail "cmux is unavailable"
    screen="$(cmux read-screen --surface "$CMUX_SURFACE_ID")"
    [[ -n "$screen" ]] || fail "the current cmux screen is empty"
    copy_text "visible screen" "$screen"
    ;;
  path|pwd) copy_text path "$(pwd -P)" ;;
  project|root) value="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd -P)"; copy_text "project path" "$value" ;;
  branch) value="$(git_value rev-parse --abbrev-ref HEAD)"; copy_text branch "$value" ;;
  commit|sha) value="$(git_value rev-parse HEAD)"; copy_text commit "$value" ;;
  remote) value="$(git_value remote get-url origin)"; copy_text remote "$value" ;;
  web|url) value="$(web_url)"; copy_text "web URL" "$value" ;;
  help|-h|--help) usage ;;
  *)
    if (( $# == 1 )) && [[ -f "$1" ]]; then
      command -v pbcopy >/dev/null 2>&1 || fail "pbcopy is unavailable"
      pbcopy < "$1"
      printf 'terminal-kit: copied file %s\n' "$1"
    else
      copy_text text "$*"
    fi
    ;;
esac
