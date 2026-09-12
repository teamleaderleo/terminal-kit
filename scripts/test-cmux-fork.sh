#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/Projects/cmux/scripts" "$scratch/bin"
git -C "$scratch/Projects/cmux" init -q
printf '#!/bin/sh\nprintf "native %%s\\n" "$*" >> "$TEST_LOG"\n' > "$scratch/Projects/cmux/scripts/reload.sh"
chmod +x "$scratch/Projects/cmux/scripts/reload.sh"
printf '{}\n' > "$scratch/Projects/cmux/glaeda.apple.json"
cat > "$scratch/bin/glaeda-apple" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_LOG"
exit "${TEST_EXIT:-0}"
MOCK
chmod +x "$scratch/bin/glaeda-apple"
export TEST_LOG="$scratch/calls"
export PATH="$scratch/bin:$PATH"
export HOME="$scratch"
unset TERMINAL_KIT_CMUX_DIR TERMINAL_KIT_CMUX_TAG
[[ "$(bash "$ROOT/bin/terminal-kit" cmux path)" == "$scratch/Projects/cmux" ]]
# An uncommitted feature checkout with no remote still builds: no implicit pull.
git -C "$scratch/Projects/cmux" symbolic-ref HEAD refs/heads/feature
bash "$ROOT/bin/terminal-kit" cmux build
[[ "$(cat "$TEST_LOG")" == "warm --project $scratch/Projects/cmux --profile app" ]]
if TEST_EXIT=7 bash "$ROOT/bin/terminal-kit" cmux warm; then
  echo 'warm swallowed build failure' >&2; exit 1
fi
if TERMINAL_KIT_CMUX_TAG=custom bash "$ROOT/bin/terminal-kit" cmux warm 2>/dev/null; then
  echo 'warm ignored explicit conflicting tag' >&2; exit 1
fi
TERMINAL_KIT_CMUX_TAG=custom bash "$ROOT/bin/terminal-kit" cmux build
[[ "$(tail -1 "$TEST_LOG")" == 'native --tag custom --no-global-cli-links' ]]
echo 'cmux canonical checkout and warm build tests passed'
