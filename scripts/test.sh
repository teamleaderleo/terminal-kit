#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
    "$ROOT/config/zsh/init.zsh" \
    "$ROOT/config/zsh/terminal.zsh" \
    "$ROOT/config/zsh/tools.zsh" \
    "$ROOT/config/zsh/hints.zsh" \
    "$ROOT/config/zsh/highlight.zsh"
fi

swift_parser=""
if command -v xcrun >/dev/null 2>&1; then
  swift_parser="$(xcrun --find swiftc 2>/dev/null || true)"
fi
if [[ -z "$swift_parser" ]] && command -v swiftc >/dev/null 2>&1; then
  swift_parser="$(command -v swiftc)"
fi
if [[ -n "$swift_parser" ]]; then
  "$swift_parser" -frontend -parse "$ROOT/tools/memoryd/main.swift"
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
  "$test_root/home/.config/terminal-kit/scroll-speed" \
  "$test_root/home/.config/terminal-kit/prompt" \
  "$test_root/home/.config/terminal-kit/hints" \
  "$test_root/home/.config/terminal-kit/hints-layout-v2" \
  "$test_root/home/.config/terminal-kit/editor-wrap" \
  "$test_root/home/.config/terminal-kit/git-protocol" \
  "$test_root/home/.config/terminal-kit/memory-mode" \
  "$test_root/home/.config/terminal-kit/memory-auto" \
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
  "$test_root/home/.config/terminal-kit/scroll-speed" \
  "$test_root/home/.config/terminal-kit/prompt" \
  "$test_root/home/.config/terminal-kit/hints" \
  "$test_root/home/.config/terminal-kit/hints-layout-v2" \
  "$test_root/home/.config/terminal-kit/editor-wrap" \
  "$test_root/home/.config/terminal-kit/git-protocol" \
  "$test_root/home/.config/terminal-kit/memory-mode" \
  "$test_root/home/.config/terminal-kit/memory-auto" \
  "$test_root/home/.config/cmux/cmux.json" \
  "$test_root/home/.config/cmux/dock.json")"

[[ "$before" == "$after" ]]
[[ "$(grep -c '^# >>> terminal-kit: environment >>>$' "$test_root/home/.zshenv")" == 1 ]]
[[ "$(grep -c '^# >>> terminal-kit: zsh >>>$' "$test_root/home/.zshrc")" == 1 ]]
[[ "$(grep -c '^# >>> terminal-kit: tmux >>>$' "$test_root/home/.tmux.conf")" == 1 ]]
[[ "$(grep -c '^# >>> terminal-kit: ghostty >>>$' "$test_root/home/.config/ghostty/config")" == 1 ]]
grep -Fq "$test_root/home/Projects/terminal-kit/config/zsh/env.zsh" "$test_root/home/.zshenv"
grep -Fq "$test_root/home/Projects/terminal-kit/config/ghostty/config" "$test_root/home/.config/ghostty/config"
grep -Fq "$test_root/home/Projects/terminal-kit/config/ghostty/appearance" "$test_root/home/.config/ghostty/config"
grep -Fq "$test_root/home/.config/terminal-kit/glass.ghostty" "$test_root/home/.config/ghostty/config"
grep -Fq 'background-blur = macos-glass-regular' "$test_root/home/.config/terminal-kit/glass.ghostty"
grep -Fq 'working-directory = home' "$test_root/home/Projects/terminal-kit/config/ghostty/config"
grep -Fq 'clipboard-trim-trailing-spaces = true' "$test_root/home/Projects/terminal-kit/config/ghostty/config"
grep -Fq 'macos-option-as-alt = left' "$test_root/home/Projects/terminal-kit/config/ghostty/config"
grep -Fq 'unfocused-split-opacity = 0.96' "$test_root/home/Projects/terminal-kit/config/ghostty/appearance"
grep -Fxq '1.4' "$test_root/home/.config/terminal-kit/scroll-speed"
grep -Fxq 'minimal' "$test_root/home/.config/terminal-kit/prompt"
grep -Fxq 'off' "$test_root/home/.config/terminal-kit/hints"
grep -Fxq 'wrap' "$test_root/home/.config/terminal-kit/editor-wrap"
grep -Fxq 'ssh' "$test_root/home/.config/terminal-kit/git-protocol"
if HOME="$test_root/home" git config --global --get-all \
  'url.git@github.com:.insteadOf' | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: legacy GitHub HTTPS-to-SSH rewrite survived install\n' >&2
  exit 1
fi
explicit_https='https://github.com/example/repository.git'
[[ "$(HOME="$test_root/home" git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]]
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
[[ "$(HOME="$test_root/home" git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]]

HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/.local/bin/terminal-kit" git ssh >/dev/null
grep -Fxq 'ssh' "$test_root/home/.config/terminal-kit/git-protocol"
grep -Fxq 'ssh' < <(tail -n 1 "$test_root/home/.config/terminal-kit/gh-test-protocols")
if HOME="$test_root/home" git config --global --get-all \
  'url.git@github.com:.insteadOf' | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: git ssh recreated legacy GitHub rewrite\n' >&2
  exit 1
fi
[[ "$(HOME="$test_root/home" git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]]

grep -Fxq 'balanced' "$test_root/home/.config/terminal-kit/memory-mode"
grep -Fxq 'off' "$test_root/home/.config/terminal-kit/memory-auto"
grep -Fq 'DispatchSource.makeMemoryPressureSource' "$test_root/home/Projects/terminal-kit/tools/memoryd/main.swift"
grep -Fq '⌘⇧P Commands' "$test_root/home/Projects/terminal-kit/config/hints.txt"
grep -Fq 'tk do task Agent worktree' "$test_root/home/Projects/terminal-kit/config/hints.txt"
grep -Fq 'tk overview All workspaces' "$test_root/home/Projects/terminal-kit/config/hints.txt"
grep -Fq 'source "$_terminal_kit_zsh_dir/hints.zsh"' "$test_root/home/Projects/terminal-kit/config/zsh/init.zsh"
grep -Fq "delta --navigate --keep-plus-minus-markers" "$test_root/home/Projects/terminal-kit/config/zsh/init.zsh"
grep -Fq "DELTA_PAGER='less -FRX'" "$test_root/home/Projects/terminal-kit/config/zsh/init.zsh"
grep -Fq 'format = "$directory$character"' "$test_root/home/Projects/terminal-kit/config/starship/terminal-kit.toml"
grep -Fq 'truncate_to_repo = true' "$test_root/home/Projects/terminal-kit/config/starship/terminal-kit.toml"
grep -Fq 'repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) "' "$test_root/home/Projects/terminal-kit/config/starship/terminal-kit.toml"
grep -Fq 'format = "$directory$git_branch$git_status$character"' "$test_root/home/Projects/terminal-kit/config/starship/detailed.toml"
grep -Fq 'HOMEBREW_NO_UPDATE_REPORT_NEW=1 brew bundle' "$test_root/home/Projects/terminal-kit/scripts/install-tools.sh"
grep -Fq 'brew "hyperfine"' "$test_root/home/Projects/terminal-kit/Brewfile"
grep -Fq 'brew "micro"' "$test_root/home/Projects/terminal-kit/Brewfile"
grep -Fq 'Usage: terminal-kit perf' "$test_root/home/Projects/terminal-kit/scripts/perf.sh"
grep -Fq 'Usage: terminal-kit memory' "$test_root/home/Projects/terminal-kit/scripts/memory.sh"
grep -Fq 'Usage: terminal-kit overview' "$test_root/home/Projects/terminal-kit/scripts/overview.sh"
grep -Fq 'Usage: terminal-kit git' "$test_root/home/Projects/terminal-kit/scripts/git.sh"
grep -Fq 'terminal-kit work [project-or-reference] [task...]' "$test_root/home/Projects/terminal-kit/scripts/work.sh"
grep -Fq 'tk do ./vmm/src/acpi.rs' "$test_root/home/Projects/terminal-kit/scripts/work.sh"
grep -Fq 'cloud-hypervisor/issues/8666' "$test_root/home/Projects/terminal-kit/scripts/work.sh"
grep -Fq -- '--border=rounded' "$test_root/home/Projects/terminal-kit/scripts/overview.sh"
grep -Fq -- '--ansi' "$test_root/home/Projects/terminal-kit/scripts/overview.sh"
grep -Fq 'overview     Browse every cmux window and workspace in one full-screen view' "$test_root/home/Projects/terminal-kit/bin/terminal-kit"
grep -Fq 'work / do    Resolve a project, make a reversible task checkout, and launch an agent' "$test_root/home/Projects/terminal-kit/bin/terminal-kit"
grep -Fq 'git          Choose SSH or HTTPS for GitHub Git operations' "$test_root/home/Projects/terminal-kit/bin/terminal-kit"
grep -Fq 'memory       Choose renderer reclamation and agent hibernation policy' "$test_root/home/Projects/terminal-kit/bin/terminal-kit"
grep -Fq '"workspaceInheritWorkingDirectory": false' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"openSupportedFilesInCmux": true' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"openMarkdownInCmuxViewer": true' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"showModifierHoldHints": true' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"showBranchDirectory": false' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"watchGitStatus": false' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"indicatorStyle": "solidFill"' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"selectionColor": "#313244"' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"scrollSpeed": 1.4' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"wordWrap": true' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"doubleClickAction": "preview"' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"maxWarmRenderers": 6' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"maxLiveTerminals": 8' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"command": "terminal-kit work"' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"command": "terminal-kit memory auto on"' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"command": "terminal-kit overview"' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"showCustomMetadata": true' "$test_root/home/.config/cmux/cmux.json"
grep -Fq '"id": "memory"' "$test_root/home/.config/cmux/dock.json"
grep -Fq "$test_root/home/Projects/terminal-kit/config/zsh/init.zsh" "$test_root/home/.zshrc"
grep -Fq "$test_root/home/Projects/terminal-kit/config/tmux/tmux.conf" "$test_root/home/.tmux.conf"
cmp -s \
  "$test_root/home/Projects/terminal-kit/config/cmux/cmux.json.example" \
  "$test_root/home/.config/cmux/cmux.json"
cmp -s \
  "$test_root/home/Projects/terminal-kit/config/cmux/dock.json.example" \
  "$test_root/home/.config/cmux/dock.json"
[[ "$(HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" path)" == "$test_root/home/Projects/terminal-kit" ]]
keys_output="$(HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" keys)"
grep -Fq 'tk keys Cheat sheet' <<< "$keys_output"
grep -Fq 'tk do task Agent worktree' <<< "$keys_output"
grep -Fq 'tk overview All workspaces' <<< "$keys_output"
perf_output="$(HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" perf status)"
grep -Fq 'terminal-kit performance settings' <<< "$perf_output"
memory_output="$(HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" memory status)"
grep -Fq 'mode:                 balanced' <<< "$memory_output"
grep -Fq 'automatic:            off' <<< "$memory_output"

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
  [[ -d "$work_path" ]]
  grep -Fxq local < <(tail -n 1 "$work_path/file.txt")
  grep -Fxq untracked "$work_path/note.txt"
  [[ "$(jq -r '.seeded_dirty' "$work_receipt")" == true ]]
  [[ "$(jq -r '.state' "$work_receipt")" == launched ]]

  printf 'agent\n' >> "$work_path/file.txt"
  printf 'new\n' > "$work_path/new.txt"
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work undo "$work_id" >/dev/null
  [[ ! -e "$work_path" ]]
  [[ "$(jq -r '.state' "$work_receipt")" == undone ]]
  recovery_head="$(jq -r '.recovery_head_ref' "$work_receipt")"
  git -C "$work_repo" show-ref --verify --quiet "$recovery_head"

  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work restore "$work_id" >/dev/null
  [[ -d "$work_path" ]]
  grep -Fq agent "$work_path/file.txt"
  grep -Fxq new "$work_path/new.txt"
  [[ "$(jq -r '.state' "$work_receipt")" == restored ]]
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
  [[ "$(jq -r '.repo_root' "$file_receipt")" == "$(cd "$work_repo" && pwd -P)" ]]
  [[ "$(jq -r '.reference' "$file_receipt")" == "$source_file_reference" ]]
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
  [[ "$(jq -r '.target' "$url_receipt")" == 'example/work-fixture' ]]
  [[ "$(jq -r '.reference' "$url_receipt")" == "$github_reference" ]]
  grep -Fq "$github_reference" < <(jq -r '.prompt' "$url_receipt")
  HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    "$test_root/home/.local/bin/terminal-kit" work undo "$url_work_id" >/dev/null
fi

printf 'terminal-kit tests passed\n'