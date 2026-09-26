#!/usr/bin/env bash
set -euo pipefail
# bash 3.2 (macOS /bin/bash) ignores set -e for a failing [[ ]]; assert explicitly.
fail_at() { printf '%s: assertion failed at line %s\n' "${0##*/}" "$1" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(cd "$(mktemp -d)" && pwd -P)"
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
  /bin/bash "$ROOT/scripts/copy.sh" command >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == 'pnpm test --filter miniflare' ]] || fail_at $LINENO

/bin/bash "$ROOT/scripts/copy.sh" path >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == "$test_root/work/project/subdir" ]] || fail_at $LINENO

/bin/bash "$ROOT/scripts/copy.sh" project >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == "$test_root/work/project" ]] || fail_at $LINENO

CMUX_SURFACE_ID='surface:1' /bin/bash "$ROOT/scripts/copy.sh" screen >/dev/null
[[ "$(cat "$TEST_CLIPBOARD")" == $'first visible line\nsecond visible line' ]] || fail_at $LINENO

printf 'terminal-kit: copy checks passed\n'
