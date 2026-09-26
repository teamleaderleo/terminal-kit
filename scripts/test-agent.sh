#!/usr/bin/env bash
set -euo pipefail
# bash 3.2 (macOS /bin/bash) ignores set -e for a failing [[ ]]; assert explicitly.
fail_at() { printf '%s: assertion failed at line %s\n' "${0##*/}" "$1" >&2; exit 1; }
trap 'printf "terminal-kit agent test failed at line %s\n" "$LINENO" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v jq >/dev/null 2>&1 || {
  printf 'terminal-kit agent test: jq is required\n' >&2
  exit 1
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
home="$scratch/home"
repo="$home/Projects/fixture"
state="$home/.local/state/terminal-kit/work"
fake_bin="$scratch/bin"
mkdir -p "$repo" "$state" "$fake_bin"

cat > "$fake_bin/cmux" <<'CMUX'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TERMINAL_KIT_TEST_CMUX_LOG:?}"
case "${1:-}" in
  ping) exit 0 ;;
  *) exit 0 ;;
esac
CMUX
chmod +x "$fake_bin/cmux"
mkdir -p "$home/.local/bin"
cp "$fake_bin/cmux" "$home/.local/bin/cmux"

original_path="$PATH"
export PATH="$fake_bin:$original_path"
export HOME="$home"
export TERMINAL_KIT_WORK_STATE_ROOT="$state"
export TERMINAL_KIT_TEST_CMUX_LOG="$scratch/cmux.log"
export CMUX_WORKSPACE_ID="workspace:test"

git -C "$repo" init -q
git -C "$repo" config user.name terminal-kit-test
git -C "$repo" config user.email terminal-kit@example.invalid
printf 'hello\n' > "$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -qm base
repo="$(cd "$repo" && pwd -P)"
head="$(git -C "$repo" rev-parse HEAD)"

id="agent-test"
receipt="$state/$id.json"
jq -n \
  --arg id "$id" \
  --arg repo "$repo" \
  --arg head "$head" \
  '{version:1,id:$id,state:"launched",created_at:"2026-08-10T00:00:00Z",repo_name:"fixture",repo_root:$repo,work_path:$repo,branch:"test",base_sha:$head,agent:"codex",launcher:"terminal",prompt:"test",reference:"",mode:"worktree",cloned:false,seeded_dirty:false}' \
  > "$receipt"
printf '%s\n' "$id" > "$state/last"

context="$(cd "$repo" && "$ROOT/bin/terminal-kit" agent context --json)"
[[ "$(printf '%s' "$context" | jq -r '.protocol')" == 'terminal-kit-agent/v1' ]] || fail_at $LINENO
[[ "$(printf '%s' "$context" | jq -r '.repository.root')" == "$repo" ]] || fail_at $LINENO
[[ "$(printf '%s' "$context" | jq -r '.work.id')" == "$id" ]] || fail_at $LINENO
printf '%s' "$context" | jq -r '.policy' | grep -Fq 'terminal-kit agent checkpoint'
printf '%s' "$context" | jq -e '.repository.guidance | type == "array"' >/dev/null

(cd "$repo" && "$ROOT/bin/terminal-kit" agent checkpoint working "implementing the thing" --proof "baseline inspected" --next "run checks") >/dev/null
[[ "$(jq -r '.state' "$receipt")" == working ]] || fail_at $LINENO
[[ "$(jq -r '.summary' "$receipt")" == 'implementing the thing' ]] || fail_at $LINENO
[[ "$(jq -r '.proof' "$receipt")" == 'baseline inspected' ]] || fail_at $LINENO
[[ "$(jq -r '.next' "$receipt")" == 'run checks' ]] || fail_at $LINENO

(cd "$repo" && "$ROOT/bin/terminal-kit" agent checkpoint done "finished the thing" --proof "tests green") >/dev/null
[[ "$(jq -r '.state' "$receipt")" == done ]] || fail_at $LINENO
[[ "$(wc -l < "$state/$id.events.jsonl" | tr -d '[:space:]')" == 2 ]] || fail_at $LINENO
jq -e 'select(.state == "working")' "$state/$id.events.jsonl" >/dev/null
jq -e 'select(.state == "done")' "$state/$id.events.jsonl" >/dev/null
grep -Fq 'workspace status set done' "$scratch/cmux.log"
grep -Fq 'notify --title fixture done' "$scratch/cmux.log"

"$ROOT/bin/terminal-kit" agent policy | grep -Fq 'Ask first'

printf 'terminal-kit agent tests passed\n'
