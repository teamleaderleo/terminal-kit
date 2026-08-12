#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/git-protocol"
GITHUB_REWRITE_KEY='url.git@github.com:.insteadOf'
GITHUB_HTTPS_PREFIX='https://github.com/'

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

set_gh_protocol() {
  local protocol="$1"
  if command -v gh >/dev/null 2>&1; then
    gh config set git_protocol "$protocol" --host github.com >/dev/null 2>&1 || true
  fi
}

add_github_ssh_rewrite() {
  local existing
  existing="$(git config --global --get-all "$GITHUB_REWRITE_KEY" 2>/dev/null || true)"
  if ! grep -Fxq "$GITHUB_HTTPS_PREFIX" <<<"$existing"; then
    git config --global --add "$GITHUB_REWRITE_KEY" "$GITHUB_HTTPS_PREFIX"
  fi
}

remove_github_ssh_rewrite() {
  git config --global --unset-all "$GITHUB_REWRITE_KEY" '^https://github\.com/$' >/dev/null 2>&1 || true
}

apply_mode() {
  local mode="$1"
  command -v git >/dev/null 2>&1 || fail "git is unavailable"
  mkdir -p "$STATE_DIR"

  case "$mode" in
    ssh)
      add_github_ssh_rewrite
      set_gh_protocol ssh
      printf 'ssh\n' >"$STATE_FILE"
      printf 'terminal-kit: GitHub Git transport set to SSH\n'
      printf 'terminal-kit: git will rewrite https://github.com/... remotes to git@github.com:...\n'
      ;;
    https)
      remove_github_ssh_rewrite
      set_gh_protocol https
      printf 'https\n' >"$STATE_FILE"
      printf 'terminal-kit: GitHub Git transport set to HTTPS\n'
      ;;
    *)
      fail "git mode must be ssh or https"
      ;;
  esac
}

current_mode() {
  local saved='ssh' rewrite='off' gh_protocol='unknown'
  [[ -r "$STATE_FILE" ]] && saved="$(tr -d '[:space:]' <"$STATE_FILE")"
  if git config --global --get-all "$GITHUB_REWRITE_KEY" 2>/dev/null | grep -Fxq "$GITHUB_HTTPS_PREFIX"; then
    rewrite='on'
  fi
  if command -v gh >/dev/null 2>&1; then
    gh_protocol="$(gh config get git_protocol --host github.com 2>/dev/null || printf unknown)"
  fi

  printf 'terminal-kit: saved GitHub protocol %s\n' "$saved"
  printf 'terminal-kit: HTTPS-to-SSH Git rewrite %s\n' "$rewrite"
  printf 'terminal-kit: gh Git protocol %s\n' "$gh_protocol"
}

apply_saved() {
  local mode='ssh'
  [[ -r "$STATE_FILE" ]] && mode="$(tr -d '[:space:]' <"$STATE_FILE")"
  case "$mode" in
    ssh|https) apply_mode "$mode" ;;
    *) fail "invalid saved GitHub protocol: $mode" ;;
  esac
}

usage() {
  cat <<'HELP'
Usage: terminal-kit git <command>

  current   Show the GitHub transport preference and active rewrite
  ssh       Use SSH for GitHub Git operations, including pasted HTTPS clone URLs
  https     Use HTTPS for GitHub Git operations and remove the terminal-kit rewrite
  apply     Reapply the saved preference

Browser links remain HTTPS. This only changes Git transport and the GitHub CLI's
clone/remote protocol.
HELP
}

command_name="${1:-current}"
shift || true

case "$command_name" in
  current|status)
    [[ $# -eq 0 ]] || fail "git current takes no arguments"
    current_mode
    ;;
  ssh)
    [[ $# -eq 0 ]] || fail "git ssh takes no arguments"
    apply_mode ssh
    ;;
  https)
    [[ $# -eq 0 ]] || fail "git https takes no arguments"
    apply_mode https
    ;;
  apply)
    [[ $# -eq 0 ]] || fail "git apply takes no arguments"
    apply_saved
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown git command: $command_name"
    ;;
esac
