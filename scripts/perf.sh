#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

require_hyperfine() {
  command -v hyperfine >/dev/null 2>&1 \
    || fail "hyperfine is missing; run 'tk tools'"
}

shell_benchmark() {
  require_hyperfine
  printf 'terminal-kit: benchmarking bare and configured login shells\n'
  hyperfine \
    --warmup 3 \
    --runs 12 \
    --command-name 'bare zsh' '/bin/zsh -dflic exit' \
    --command-name 'configured zsh' '/bin/zsh -lic exit'
}

shell_profile() {
  local profile_dir
  profile_dir="$(mktemp -d -t terminal-kit-zprof)"
  trap 'rm -rf "$profile_dir"' EXIT

  cat >"$profile_dir/.zshenv" <<'EOF_ZSHENV'
zmodload zsh/zprof
[[ -r "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
EOF_ZSHENV

  cat >"$profile_dir/.zprofile" <<'EOF_ZPROFILE'
[[ -r "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
EOF_ZPROFILE

  cat >"$profile_dir/.zshrc" <<'EOF_ZSHRC'
[[ -r "$HOME/.zshrc" ]] && source "$HOME/.zshrc"
printf '\nterminal-kit: Zsh startup profile (largest total times first)\n'
zprof
EOF_ZSHRC

  ZDOTDIR="$profile_dir" /bin/zsh -lic exit
}

cmux_resources() {
  command -v cmux >/dev/null 2>&1 || fail "cmux CLI not found"
  if cmux ping >/dev/null 2>&1; then
    printf 'terminal-kit: cmux resource tree\n'
    cmux top
  else
    fail "cmux is not running or socket control is unavailable"
  fi
}

show_status() {
  local config="$HOME/.config/cmux/cmux.json"
  printf 'terminal-kit performance settings\n'

  if [[ -r "$config" ]] && command -v jq >/dev/null 2>&1; then
    printf '  Git sidebar watcher:  %s\n' "$(jq -r '.sidebar.watchGitStatus // true' "$config")"
    printf '  renderer reclamation: cmux default (enabled)\n'
    printf '  agent hibernation:    %s\n' "$(jq -r 'if .terminal.agentHibernation.enabled == true then "enabled" else "off" end' "$config")"
  else
    printf '  cmux config:           unavailable\n'
  fi

  if command -v hyperfine >/dev/null 2>&1; then
    printf '  benchmark tool:        %s\n' "$(command -v hyperfine)"
  else
    printf '  benchmark tool:        missing (run tk tools)\n'
  fi
}

usage() {
  cat <<'HELP'
Usage: terminal-kit perf <command>

  status       Show the performance-related cmux settings
  shell        Benchmark bare versus configured Zsh startup
  profile      Profile Zsh startup functions with zprof
  cmux         Show cmux resource use by window, workspace, pane, and surface
  all          Run status, shell benchmark, and cmux resource report
HELP
}

command_name="${1:-status}"
shift || true

case "$command_name" in
  status|current)
    show_status
    ;;
  shell|benchmark)
    shell_benchmark
    ;;
  profile|zprof)
    shell_profile
    ;;
  cmux|resources|top)
    cmux_resources
    ;;
  all)
    show_status
    printf '\n'
    shell_benchmark
    printf '\n'
    cmux_resources
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown perf command: $command_name"
    ;;
esac
