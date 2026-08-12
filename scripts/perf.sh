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

navigation_benchmark() {
  command -v cmux >/dev/null 2>&1 || fail "cmux CLI not found"
  command -v jq >/dev/null 2>&1 || fail "jq is required for the navigation benchmark"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required for the navigation benchmark"
  cmux ping >/dev/null 2>&1 || fail "cmux is not running or socket control is unavailable"

  local current_workspace="${CMUX_WORKSPACE_ID:-}"
  local current_surface="${CMUX_SURFACE_ID:-}"
  if [[ -z "$current_workspace" || -z "$current_surface" ]]; then
    fail "run 'tk perf nav' from a cmux terminal so the current workspace and surface are known"
  fi

  local tree_json workspaces_json other_surface other_workspace
  tree_json="$(cmux tree --workspace "$current_workspace" --json --id-format both)"
  workspaces_json="$(cmux list-workspaces --json --id-format both)"

  other_surface="$(printf '%s\n' "$tree_json" | jq -r --arg current "$current_surface" '
    [
      .. | objects
      | select(((.ref? // "") | startswith("surface:")))
      | (.id // .ref)
    ]
    | unique
    | map(select(. != $current))
    | .[0] // empty
  ')"

  other_workspace="$(printf '%s\n' "$workspaces_json" | jq -r --arg current "$current_workspace" '
    [
      .. | objects
      | select(((.ref? // "") | startswith("workspace:")))
      | (.id // .ref)
    ]
    | unique
    | map(select(. != $current))
    | .[0] // empty
  ')"

  printf 'terminal-kit: cmux navigation control round-trip\n'
  printf '  note: this times acknowledged focus/select operations, not the final painted frame\n'

  if [[ -n "$other_surface" ]]; then
    python3 - "$current_workspace" "$current_surface" "$other_surface" <<'PY'
import statistics
import subprocess
import sys
import time

workspace, current, other = sys.argv[1:]

def cmux(*args):
    subprocess.run(["cmux", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

samples = []
for _ in range(12):
    started = time.perf_counter()
    cmux("focus-panel", "--workspace", workspace, "--panel", other)
    cmux("focus-panel", "--workspace", workspace, "--panel", current)
    samples.append((time.perf_counter() - started) * 500.0)

print(f"  surface/tab median:    {statistics.median(samples):6.2f} ms per switch")
PY
  else
    printf '  surface/tab median:    unavailable (current workspace has one surface)\n'
  fi

  if [[ -n "$other_workspace" ]]; then
    python3 - "$current_workspace" "$other_workspace" <<'PY'
import statistics
import subprocess
import sys
import time

current, other = sys.argv[1:]

def cmux(*args):
    subprocess.run(["cmux", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

samples = []
for _ in range(12):
    started = time.perf_counter()
    cmux("select-workspace", "--workspace", other)
    cmux("select-workspace", "--workspace", current)
    samples.append((time.perf_counter() - started) * 500.0)

print(f"  workspace median:      {statistics.median(samples):6.2f} ms per switch")
PY
  else
    printf '  workspace median:      unavailable (only one workspace is open)\n'
  fi

  cmux select-workspace --workspace "$current_workspace" >/dev/null 2>&1 || true
  printf '  expectation: surface/tab switching is the lighter path; warm renderers keep workspace switching close\n'
}

show_status() {
  local config="$HOME/.config/cmux/cmux.json"
  printf 'terminal-kit performance settings\n'

  if command -v cmux >/dev/null 2>&1; then
    printf '  cmux version:          %s\n' "$(cmux --version 2>/dev/null | head -n 1)"
  else
    printf '  cmux version:          missing\n'
  fi

  if [[ -r "$config" ]] && command -v jq >/dev/null 2>&1; then
    printf '  Git sidebar watcher:  %s\n' "$(jq -r '.sidebar.watchGitStatus // true' "$config")"
    printf '  warm renderers:       %s\n' "$(jq -r '.terminal.rendererRealization.maxWarmRenderers // "default"' "$config")"
    printf '  renderer idle delay:  %ss\n' "$(jq -r '.terminal.rendererRealization.idleSeconds // "default"' "$config")"
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
  nav          Compare live cmux surface/tab and workspace switch control latency
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
  nav|navigation)
    navigation_benchmark
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
