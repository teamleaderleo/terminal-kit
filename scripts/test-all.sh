#!/usr/bin/env bash
# The one test entry point: `tk test` and CI both run this.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Never reload the live cmux, Ghostty, or tmux from a test run.
export TERMINAL_KIT_NO_RELOAD=1

tests=(
  test.sh
  test-update.sh
  test-copy.sh
  test-ergonomics.sh
  test-familiar-controls.sh
  test-prompt-clipboard.sh
  test-navigation.sh
  test-agent.sh
  test-karabiner.sh
  test-shell-helpers.sh
  test-shell-dispatch.sh
  test-shell-env.sh
  test-cmux-fork.sh
  test-git-checkout.py
  test-cmux-audit.py
  test-recent.py
  test-work-history.js
)

for name in "${tests[@]}"; do
  printf '== %s\n' "$name"
  case "$name" in
    *.sh) bash "$ROOT/scripts/$name" ;;
    *.py) python3 "$ROOT/scripts/$name" ;;
    *.js) node "$ROOT/scripts/$name" ;;
  esac
done

printf 'terminal-kit: all tests passed\n'
