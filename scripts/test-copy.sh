#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/work/project/subdir"

cat > "$test_root/bin/pbcopy" <<'FAKE_PBCOPY'
#!/usr/bin/env bash
cat > "$TEST_CLIPBOARD"
FAKE_PBCOPY

cat > "$test_root/bin/cmux" <<'FAKE_CMUX'
#!/usr/bin/env bash
if [[ "${1:-}" == "read-screen" ]]; then
  printf 'first visible line\nsecond visible line\n'
  exit 0
fi
exit 2
FAKE_CMUX

cat > "$test_root/bin/git" <<'FAKE_GIT'
#!/usr/bin/env bash
if [[ "$*" == *'rev-parse --show-toplevel'* ]]; then
  printf '%s\n' "$TEST_PROJECT_ROOT"
  exit 0
fi
exit 2
FAKE_GIT

chmod +x "$test_root/bin/pbcopy" "$test_root/bin/cmux" "$test_root/bin/git"
export PATH="$test_root/bin:/usr/bin:/bin"
export TEST_CLIPBOARD="$test_root/clipboard"
export TEST_PROJECT_ROOT="$test_root/work/project"

cd "$test_root/work/project/subdir"

TERMINAL_KIT_LAST_COMMAND='pnpm test --filter miniflare' \
  "$ROOT/scripts/copy.sh" command >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == 'pnpm test --filter miniflare' ]]

"$ROOT/scripts/copy.sh" path >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == "$test_root/work/project/subdir" ]]

"$ROOT/scripts/copy.sh" project >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == "$test_root/work/project" ]]

CMUX_SURFACE_ID='surface:1' "$ROOT/scripts/copy.sh" screen >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == $'first visible line\nsecond visible line' ]]

grep -Fq '"showBranchDirectory": false' "$ROOT/config/cmux/cmux.json.example"
grep -Fq '"target": "currentTerminal"' "$ROOT/config/cmux/cmux.json.example"
grep -Fq '"action": "terminal-kit.copyScreen"' "$ROOT/config/cmux/cmux.json.example"
grep -Fq "bindkey '^I' expand-or-complete" "$ROOT/config/zsh/terminal.zsh"
grep -Fq 'compinit -i -d "$_terminal_kit_compdump"' "$ROOT/config/zsh/init.zsh"
grep -Fq 'git -C "$PWD" rev-parse --show-toplevel' "$ROOT/config/zsh/terminal.zsh"

printf 'terminal-kit: clipboard, sidebar title, and completion checks passed\n'
