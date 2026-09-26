#!/usr/bin/env bash
set -euo pipefail
# bash 3.2 (macOS /bin/bash) ignores set -e for a failing [[ ]]; assert explicitly.
fail_at() { printf '%s: assertion failed at line %s\n' "${0##*/}" "$1" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Never reload the live cmux, Ghostty, or tmux from a fake-HOME test run.
export TERMINAL_KIT_NO_RELOAD=1
trap 'printf "terminal-kit: test.sh failed at line %s\n" "$LINENO" >&2' ERR

validate_json() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq empty "$file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    json.load(handle)
PY
  else
    printf 'terminal-kit: JSON validation requires jq or python3\n' >&2
    return 1
  fi
}

for file in "$ROOT/install.sh" "$ROOT/bin/terminal-kit" "$ROOT/scripts/"*.sh; do
  bash -n "$file"
done

if command -v zsh >/dev/null 2>&1; then
  zsh -n \
    "$ROOT/config/zsh/env.zsh" \
    "$ROOT/config/zsh/cache.zsh" \
    "$ROOT/config/zsh/init.zsh" \
    "$ROOT/config/zsh/terminal.zsh" \
    "$ROOT/config/zsh/tools.zsh" \
    "$ROOT/config/zsh/update.zsh" \
    "$ROOT/config/zsh/highlight.zsh"
fi

validate_json "$ROOT/config/cmux/cmux.json.example"
validate_json "$ROOT/config/cmux/dock.json.example"

# Exercise repeated installs from a repo that stays inside ~/Projects.
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home/Projects" "$test_root/bin"
cp -R "$ROOT" "$test_root/home/Projects/terminal-kit"
cat > "$test_root/bin/uname" <<'FAKE_UNAME'
#!/usr/bin/env bash
echo Darwin
FAKE_UNAME
chmod +x "$test_root/bin/uname"

# Simulate an older terminal-kit install. Current installs must clean this global
# rewrite instead of preserving or recreating it.
HOME="$test_root/home" git config --global \
  url.git@github.com:.insteadOf https://github.com/

HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/Projects/terminal-kit/install.sh" --skip-tools >/dev/null

before="$(shasum \
  "$test_root/home/.zshenv" \
  "$test_root/home/.zshrc" \
  "$test_root/home/.tmux.conf" \
  "$test_root/home/.config/ghostty/config" \
  "$test_root/home/.config/terminal-kit/glass.ghostty" \
  "$test_root/home/.config/terminal-kit/settings.json" \
  "$test_root/home/.config/terminal-kit/git-protocol" \
  "$test_root/home/.config/cmux/cmux.json" \
  "$test_root/home/.config/cmux/dock.json")"
HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/Projects/terminal-kit/install.sh" --skip-tools >/dev/null
after="$(shasum \
  "$test_root/home/.zshenv" \
  "$test_root/home/.zshrc" \
  "$test_root/home/.tmux.conf" \
  "$test_root/home/.config/ghostty/config" \
  "$test_root/home/.config/terminal-kit/glass.ghostty" \
  "$test_root/home/.config/terminal-kit/settings.json" \
  "$test_root/home/.config/terminal-kit/git-protocol" \
  "$test_root/home/.config/cmux/cmux.json" \
  "$test_root/home/.config/cmux/dock.json")"

[[ "$before" == "$after" ]] || fail_at $LINENO
[[ "$(grep -c '^# >>> terminal-kit: environment >>>$' "$test_root/home/.zshenv")" == 1 ]] || fail_at $LINENO
[[ "$(grep -c '^# >>> terminal-kit: zsh >>>$' "$test_root/home/.zshrc")" == 1 ]] || fail_at $LINENO
[[ "$(grep -c '^# >>> terminal-kit: tmux >>>$' "$test_root/home/.tmux.conf")" == 1 ]] || fail_at $LINENO
[[ "$(grep -c '^# >>> terminal-kit: ghostty >>>$' "$test_root/home/.config/ghostty/config")" == 1 ]] || fail_at $LINENO
grep -Fq "$test_root/home/Projects/terminal-kit/config/zsh/env.zsh" "$test_root/home/.zshenv"
grep -Fq "$test_root/home/Projects/terminal-kit/config/ghostty/config" "$test_root/home/.config/ghostty/config"
grep -Fq "$test_root/home/Projects/terminal-kit/config/ghostty/appearance" "$test_root/home/.config/ghostty/config"
grep -Fq "$test_root/home/.config/terminal-kit/glass.ghostty" "$test_root/home/.config/ghostty/config"
grep -Fq 'background-blur = macos-glass-regular' "$test_root/home/.config/terminal-kit/glass.ghostty"
grep -Fxq 'ssh' "$test_root/home/.config/terminal-kit/git-protocol"
if HOME="$test_root/home" git config --global --get-all \
  'url.git@github.com:.insteadOf' | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: legacy GitHub HTTPS-to-SSH rewrite survived install\n' >&2
  exit 1
fi
explicit_https='https://github.com/example/repository.git'
[[ "$(HOME="$test_root/home" git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]] || fail_at $LINENO
git_status="$(HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/.local/bin/terminal-kit" git current)"
grep -Fq 'terminal-kit: saved GitHub protocol ssh' <<< "$git_status"
grep -Fq 'terminal-kit: legacy HTTPS-to-SSH Git rewrite off' <<< "$git_status"

# Exercise GitHub CLI protocol selection without requiring a real gh login. The
# dispatcher prepends ~/.local/bin to PATH, so place the fixture there to keep a
# host-installed gh from shadowing it.
cat > "$test_root/home/.local/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
if [[ "${1:-}" == config && "${2:-}" == set && "${3:-}" == git_protocol ]]; then
  printf '%s\n' "${4:-}" >> "$HOME/.config/terminal-kit/gh-test-protocols"
  exit 0
fi
if [[ "${1:-}" == config && "${2:-}" == get && "${3:-}" == git_protocol ]]; then
  tail -n 1 "$HOME/.config/terminal-kit/gh-test-protocols" 2>/dev/null || printf 'unknown\n'
  exit 0
fi
exit 1
FAKE_GH
chmod +x "$test_root/home/.local/bin/gh"

HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/.local/bin/terminal-kit" git https >/dev/null
grep -Fxq 'https' "$test_root/home/.config/terminal-kit/git-protocol"
grep -Fxq 'https' < <(tail -n 1 "$test_root/home/.config/terminal-kit/gh-test-protocols")
if HOME="$test_root/home" git config --global --get-all \
  'url.git@github.com:.insteadOf' | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: git https recreated legacy GitHub rewrite\n' >&2
  exit 1
fi
[[ "$(HOME="$test_root/home" git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]] || fail_at $LINENO

HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/.local/bin/terminal-kit" git ssh >/dev/null
grep -Fxq 'ssh' "$test_root/home/.config/terminal-kit/git-protocol"
grep -Fxq 'ssh' < <(tail -n 1 "$test_root/home/.config/terminal-kit/gh-test-protocols")
if HOME="$test_root/home" git config --global --get-all \
  'url.git@github.com:.insteadOf' | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: git ssh recreated legacy GitHub rewrite\n' >&2
  exit 1
fi
[[ "$(HOME="$test_root/home" git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]] || fail_at $LINENO

tk_home() {
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" "$@"
}
cmux_value() {
  python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): v=v[k]
print(json.dumps(v))' "$test_root/home/.config/cmux/cmux.json" "$1"
}
state_dir="$test_root/home/.config/terminal-kit"

# A fresh install stores no overrides and renders the template defaults.
[[ "$(tk_home set scroll)" == 1.4 ]] || fail_at $LINENO
[[ "$(tk_home set prompt)" == minimal ]] || fail_at $LINENO
[[ "$(cmux_value terminal.scrollSpeed)" == 1.4 ]] || fail_at $LINENO
[[ "$(cmux_value terminal.rendererRealization.maxWarmRenderers)" == 12 ]] || fail_at $LINENO
[[ "$(cmux_value fileEditor.wordWrap)" == true ]] || fail_at $LINENO
[[ "$(cmux_value sidebar.showPullRequests)" == false ]] || fail_at $LINENO
[[ "$(cmux_value '$schema')" == *cmux.schema.json* ]] || fail_at $LINENO
grep -Fq 'background-blur = macos-glass-regular' "$state_dir/glass.ghostty"

# Pre-settings.json installs keep their choices: legacy per-setting files are
# migrated once, then removed.
rm -f "$state_dir/settings.json"
printf '1.8\n' > "$state_dir/scroll-speed"
printf 'wide\n' > "$state_dir/editor-wrap"
printf 'detailed\n' > "$state_dir/prompt"
printf 'balanced\n' > "$state_dir/memory-mode"
printf 'off\n' > "$state_dir/memory-auto"
printf '# terminal-kit glass preset: clear\nbackground-opacity = 0.92\n' > "$state_dir/glass.ghostty"
HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/Projects/terminal-kit/install.sh" --skip-tools >/dev/null
for legacy in scroll-speed editor-wrap prompt memory-mode memory-auto; do
  [[ ! -e "$state_dir/$legacy" ]] || fail_at $LINENO
done
[[ "$(tk_home set scroll)" == 1.8 ]] || fail_at $LINENO
[[ "$(tk_home set wrap)" == wide ]] || fail_at $LINENO
[[ "$(tk_home set prompt)" == detailed ]] || fail_at $LINENO
[[ "$(tk_home set memory)" == normal ]] || fail_at $LINENO
[[ "$(tk_home set glass)" == clear ]] || fail_at $LINENO
[[ "$(cmux_value terminal.scrollSpeed)" == 1.8 ]] || fail_at $LINENO
[[ "$(cmux_value fileEditor.wordWrap)" == false ]] || fail_at $LINENO
grep -Fq 'background-blur = macos-glass-clear' "$state_dir/glass.ghostty"
# The shell reads the prompt mode straight from settings.json.
grep -Fq '"prompt": "detailed"' "$state_dir/settings.json"

# tk set changes one key and re-renders; an unchanged value rewrites nothing.
tk_home set memory lean >/dev/null
[[ "$(cmux_value terminal.rendererRealization.maxWarmRenderers)" == 2 ]] || fail_at $LINENO
[[ "$(cmux_value terminal.agentHibernation.enabled)" == true ]] || fail_at $LINENO
tk_home set sidebar details >/dev/null
[[ "$(cmux_value sidebar.showPullRequests)" == true ]] || fail_at $LINENO
[[ "$(cmux_value terminal.scrollSpeed)" == 1.8 ]] || fail_at $LINENO
cmux_stamp="$(stat -f '%i %m' "$test_root/home/.config/cmux/cmux.json")"
sleep 1
tk_home set sidebar details >/dev/null
[[ "$(stat -f '%i %m' "$test_root/home/.config/cmux/cmux.json")" == "$cmux_stamp" ]] || fail_at $LINENO
tk_home set memory default >/dev/null
[[ "$(cmux_value terminal.rendererRealization.maxWarmRenderers)" == 12 ]] || fail_at $LINENO
if tk_home set scroll 9 2>/dev/null; then exit 1; fi
if tk_home set memory ultra 2>/dev/null; then exit 1; fi
if tk_home set nonsense 1 2>/dev/null; then exit 1; fi
if tk_home scroll fast 2>/dev/null; then exit 1; fi
[[ "$(tk_home set scroll)" == 1.8 ]] || fail_at $LINENO
tk_home set >/dev/null

# A hand edit to cmux.json is backed up before the renderer replaces it.
printf '{}\n' > "$test_root/home/.config/cmux/cmux.json"
tk_home set scroll 1.4 >/dev/null
[[ "$(cmux_value terminal.scrollSpeed)" == 1.4 ]] || fail_at $LINENO
grep -rlq '^{}$' "$test_root/home/.config/terminal-kit-backups"

grep -Fq "$test_root/home/Projects/terminal-kit/config/zsh/init.zsh" "$test_root/home/.zshrc"
grep -Fq "$test_root/home/Projects/terminal-kit/config/tmux/tmux.conf" "$test_root/home/.tmux.conf"
cmp -s \
  "$test_root/home/Projects/terminal-kit/config/cmux/dock.json.example" \
  "$test_root/home/.config/cmux/dock.json"
[[ "$(tk_home path)" == "$(cd "$test_root/home/Projects/terminal-kit" && pwd -P)" ]] || fail_at $LINENO
grep -Fq 'tk keys' < <(tk_home keys)
grep -Fq 'terminal-kit performance settings' < <(tk_home perf status)

# Exercise the reversible worktree lifecycle and reference routing. A fake cmux
# accepts workspace creation so the test never starts a real coding agent.
if command -v jq >/dev/null 2>&1; then
  cat > "$test_root/bin/cmux" <<'FAKE_CMUX'
#!/usr/bin/env bash
case "${1:-}" in
  ping) exit 0 ;;
  new-workspace) exit 0 ;;
  *) exit 0 ;;
esac
FAKE_CMUX
  chmod +x "$test_root/bin/cmux"
  # The installed front door prepends ~/.local/bin and Homebrew. Keep both
  # launch routes local to the fixture even when cmux-chat is installed.
  cp "$test_root/bin/cmux" "$test_root/home/.local/bin/cmux"
  cp "$test_root/bin/cmux" "$test_root/home/.local/bin/cmux-chat"

  work_repo="$test_root/home/Projects/work-fixture"
  mkdir -p "$work_repo"
  git -C "$work_repo" init -q
  git -C "$work_repo" config user.name terminal-kit-test
  git -C "$work_repo" config user.email terminal-kit@example.invalid
  printf 'base\n' > "$work_repo/file.txt"
  git -C "$work_repo" add file.txt
  git -C "$work_repo" commit -qm base
  printf 'local\n' >> "$work_repo/file.txt"
  printf 'untracked\n' > "$work_repo/note.txt"

  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work "$work_repo" "test reversible task" >/dev/null
  work_id="$(tr -d '[:space:]' < "$test_root/home/.local/state/terminal-kit/work/last")"
  work_receipt="$test_root/home/.local/state/terminal-kit/work/$work_id.json"
  work_path="$(jq -r '.work_path' "$work_receipt")"
  [[ -d "$work_path" ]] || fail_at $LINENO
  grep -Fxq local < <(tail -n 1 "$work_path/file.txt")
  grep -Fxq untracked "$work_path/note.txt"
  [[ "$(jq -r '.seeded_dirty' "$work_receipt")" == true ]] || fail_at $LINENO
  [[ "$(jq -r '.state' "$work_receipt")" == launched ]] || fail_at $LINENO

  printf 'agent\n' >> "$work_path/file.txt"
  printf 'new\n' > "$work_path/new.txt"
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work undo "$work_id" >/dev/null
  [[ ! -e "$work_path" ]] || fail_at $LINENO
  [[ "$(jq -r '.state' "$work_receipt")" == undone ]] || fail_at $LINENO
  recovery_head="$(jq -r '.recovery_head_ref' "$work_receipt")"
  git -C "$work_repo" show-ref --verify --quiet "$recovery_head"

  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work restore "$work_id" >/dev/null
  [[ -d "$work_path" ]] || fail_at $LINENO
  grep -Fq agent "$work_path/file.txt"
  grep -Fxq new "$work_path/new.txt"
  [[ "$(jq -r '.state' "$work_receipt")" == restored ]] || fail_at $LINENO
  if grep -Fq agent "$work_repo/file.txt"; then
    printf 'terminal-kit: agent work leaked into source checkout\n' >&2
    exit 1
  fi

  # A local file routes back to its containing repo and survives in the receipt.
  source_file_reference="$(cd "$work_repo" && pwd -P)/file.txt"
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work "$work_repo/file.txt" "inspect this file" >/dev/null
  file_work_id="$(tr -d '[:space:]' < "$test_root/home/.local/state/terminal-kit/work/last")"
  file_receipt="$test_root/home/.local/state/terminal-kit/work/$file_work_id.json"
  [[ "$(jq -r '.repo_root' "$file_receipt")" == "$(cd "$work_repo" && pwd -P)" ]] || fail_at $LINENO
  [[ "$(jq -r '.reference' "$file_receipt")" == "$source_file_reference" ]] || fail_at $LINENO
  grep -Fq 'inspect this file' < <(jq -r '.prompt' "$file_receipt")
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work undo "$file_work_id" >/dev/null

  # A GitHub deep link routes to owner/repo. An existing repo with that basename
  # prevents network access while exercising the same resolver path.
  github_reference='https://github.com/example/work-fixture/issues/7'
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work "$github_reference" >/dev/null
  url_work_id="$(tr -d '[:space:]' < "$test_root/home/.local/state/terminal-kit/work/last")"
  url_receipt="$test_root/home/.local/state/terminal-kit/work/$url_work_id.json"
  [[ "$(jq -r '.target' "$url_receipt")" == 'example/work-fixture' ]] || fail_at $LINENO
  [[ "$(jq -r '.reference' "$url_receipt")" == "$github_reference" ]] || fail_at $LINENO
  grep -Fq "$github_reference" < <(jq -r '.prompt' "$url_receipt")
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work undo "$url_work_id" >/dev/null
fi

# Uninstall removes every managed block and the command, and keeps user lines.
printf 'export USER_LINE=1\n' >> "$test_root/home/.zshrc"
HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  /bin/bash "$test_root/home/Projects/terminal-kit/scripts/uninstall.sh" >/dev/null
for host in .zshenv .zshrc .tmux.conf .config/ghostty/config; do
  if grep -Fq '# >>> terminal-kit:' "$test_root/home/$host"; then fail_at $LINENO; fi
done
grep -Fxq 'export USER_LINE=1' "$test_root/home/.zshrc"
[[ ! -e "$test_root/home/.local/bin/terminal-kit" ]] || fail_at $LINENO
[[ -e "$test_root/home/.config/cmux/cmux.json" ]] || fail_at $LINENO

printf 'terminal-kit install and work tests passed\n'
