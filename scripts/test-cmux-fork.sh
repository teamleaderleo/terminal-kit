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
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_LOG"
[[ -z "${TEST_STDOUT:-}" ]] || printf '%s\n' "$TEST_STDOUT"
[[ -z "${TEST_STDERR:-}" ]] || printf '%s\n' "$TEST_STDERR" >&2
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
# Generation selection is explicit, validated locally, and never silently ignored.
for action in warm build; do
  bash "$ROOT/bin/terminal-kit" cmux "$action" --generation recovery-1 2>"$scratch/stderr"
  [[ "$(tail -1 "$TEST_LOG")" == "warm --project $scratch/Projects/cmux --profile app --generation recovery-1" ]]
  grep -q 'cold build' "$scratch/stderr"
done
valid_long="$(printf 'a%.0s' {1..64})"
bash "$ROOT/bin/terminal-kit" cmux warm --generation "$valid_long" 2>/dev/null
[[ "$(tail -1 "$TEST_LOG")" == *"--generation $valid_long" ]]
expect_rejected() {
  local before after
  before="$(wc -l < "$TEST_LOG")"
  if bash "$ROOT/bin/terminal-kit" cmux "$@" >"$scratch/stdout" 2>"$scratch/stderr"; then
    echo "unexpectedly accepted cmux $*" >&2; exit 1
  fi
  after="$(wc -l < "$TEST_LOG")"
  [[ "$before" == "$after" ]]
}
for label in '' '-bad' 'Bad' 'has space' 'a/b' 'with_under' 'é' "${valid_long}a"; do
  expect_rejected warm --generation "$label"
done
expect_rejected warm --generation
expect_rejected build --generation
expect_rejected warm --generation one --generation two
expect_rejected build --unknown
expect_rejected warm stray
TERMINAL_KIT_CMUX_TAG=custom expect_rejected build --generation recovery-1

# Refusals remain machine-readable, with actionable advice and exact exit codes.
refusal='{"schema_version":1,"state":"refused","reason":"cache was interrupted; choose a new --generation for a cold rebuild"}'
result=0
TEST_EXIT=2 TEST_STDERR="$(printf 'native progress\n42\n%s' "$refusal")" bash "$ROOT/bin/terminal-kit" cmux warm >"$scratch/stdout" 2>"$scratch/stderr" || result=$?
[[ "$result" == 2 && ! -s "$scratch/stdout" ]]
grep -Fq "$refusal" "$scratch/stderr"
grep -Fq 'tk cmux warm --generation <new-label>' "$scratch/stderr"
for status in 0 2 7 130; do
  result=0
  TEST_EXIT="$status" TEST_STDOUT='build output' TEST_STDERR='ordinary diagnostic' \
    bash "$ROOT/bin/terminal-kit" cmux warm >"$scratch/stdout" 2>"$scratch/stderr" || result=$?
  [[ "$result" == "$status" ]]
  [[ "$(cat "$scratch/stdout")" == 'build output' ]]
  [[ "$(cat "$scratch/stderr")" == 'ordinary diagnostic' ]]
done
echo 'cmux canonical checkout and warm build tests passed'
