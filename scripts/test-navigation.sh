#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/apply.sh" "$ROOT/scripts/perf.sh"

# The portable path stays direct in cmux; Cmd-Tab remains the macOS alias layer.
if command -v jq >/dev/null 2>&1; then
  [[ "$(jq -r '.shortcuts.bindings.nextSurface' "$ROOT/config/cmux/cmux.json.example")" == 'ctrl+tab' ]]
  [[ "$(jq -r '.shortcuts.bindings.prevSurface' "$ROOT/config/cmux/cmux.json.example")" == 'ctrl+shift+tab' ]]
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

printf 'terminal-kit navigation responsiveness checks passed\n'
