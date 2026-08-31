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

grep -Fq 'navigation-cache-v1' "$ROOT/scripts/apply.sh"
grep -Fq 'maxWarmRenderers: 12' "$ROOT/scripts/apply.sh"
grep -Fq "printf 'normal\\n' > \"\$memory_state\"" "$ROOT/scripts/apply.sh"
grep -Fq 'Cmd-Tab alias is missing from Karabiner' "$ROOT/scripts/apply.sh"
grep -Fq 'cmux config doctor' "$ROOT/scripts/apply.sh"

grep -Fq 'Usage: terminal-kit perf <command>' "$ROOT/scripts/perf.sh"
grep -Fq 'nav          Compare live cmux surface/tab and workspace switch control latency' "$ROOT/scripts/perf.sh"
grep -Fq 'focus-panel' "$ROOT/scripts/perf.sh"
grep -Fq 'select-workspace' "$ROOT/scripts/perf.sh"
grep -Fq 'not the final painted frame' "$ROOT/scripts/perf.sh"

# A failed bare-name cd can fall through to an exact project basename without
# changing any successful native cd behavior.
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/config/zsh/navigation.zsh"

  navigation_tmp="$(mktemp -d)"
  trap 'rm -rf "$navigation_tmp"' EXIT
  mkdir -p \
    "$navigation_tmp/home/Projects/cloud-hypervisor" \
    "$navigation_tmp/home/scratch/local" \
    "$navigation_tmp/a/duplicate" \
    "$navigation_tmp/b/duplicate"

  HOME="$navigation_tmp/home" zsh -f -c '
    set -e
    source "$1"

    # Project fallback canonicalizes the chosen target with `pwd -P`; successful
    # native cd forms must keep Zsh's ordinary logical $PWD behavior.
    project_expected="$(builtin cd -- "$HOME/Projects/cloud-hypervisor" && pwd -P)"

    cd "$HOME/scratch"
    cd cloud-hypervisor
    [[ "$PWD" == "$project_expected" ]]

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
