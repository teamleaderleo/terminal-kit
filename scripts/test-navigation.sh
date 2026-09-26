#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/apply.sh" "$ROOT/scripts/perf.sh"

# The portable path stays direct in cmux; Cmd-Tab remains the macOS alias layer.
if command -v jq >/dev/null 2>&1; then
  [[ "$(jq -r '.shortcuts.bindings.nextSurface' "$ROOT/config/cmux/cmux.json.example")" == 'ctrl+tab' ]]
  [[ "$(jq -r '.shortcuts.bindings.prevSurface' "$ROOT/config/cmux/cmux.json.example")" == 'ctrl+shift+tab' ]]
  [[ "$(jq -r '.terminal.showTextBoxOnNewTerminals' "$ROOT/config/cmux/cmux.json.example")" == 'false' ]]
fi

# A failed bare-name cd can fall through to an exact project basename without
# changing any successful native cd behavior.
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/config/zsh/navigation.zsh"

  navigation_tmp="$(mktemp -d)"
  navigation_tmp="$(cd "$navigation_tmp" && pwd -P)"
  trap 'rm -rf "$navigation_tmp"' EXIT
  mkdir -p \
    "$navigation_tmp/home/Projects/cloud-hypervisor" \
    "$navigation_tmp/home/scratch/local" \
    "$navigation_tmp/a/duplicate" \
    "$navigation_tmp/b/duplicate"

  HOME="$navigation_tmp/home" zsh -f -c '
    set -e
    source "$1"

    cd "$HOME/scratch"
    cd cloud-hypervisor
    [[ "$PWD" == "$HOME/Projects/cloud-hypervisor" ]]

    cd "$HOME/scratch"
    cd local
    [[ "$PWD" == "$HOME/scratch/local" ]]

    cd "$HOME/scratch/local"
    cd ..
    [[ "$PWD" == "$HOME/scratch" ]]

    export TERMINAL_KIT_PROJECT_DIRS="$2/a:$2/b"
    cd "$HOME/scratch"
    if cd duplicate 2>/dev/null; then
      print -u2 "ambiguous project basename unexpectedly resolved"
      exit 1
    fi
    [[ "$PWD" == "$HOME/scratch" ]]
  ' terminal-kit-navigation "$ROOT/config/zsh/navigation.zsh" "$navigation_tmp"
fi

printf 'terminal-kit navigation responsiveness checks passed\n'
