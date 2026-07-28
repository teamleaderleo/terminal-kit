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
grep -Fq '⌘⇧P Commands' "$test_root/home/Projects/terminal-kit/config/hints.txt"
grep -Fq 'source "$_terminal_kit_zsh_dir/hints.zsh"' "$test_root/home/Projects/terminal-kit/config/zsh/init.zsh"
grep -Fq 'format = "$directory$character"' "$test_root/home/Projects/terminal-kit/config/starship/terminal-kit.toml"
grep -Fq 'format = "$directory$git_branch$git_status$character"' "$test_root/home/Projects/terminal-kit/config/starship/detailed.toml"
grep -Fq 'brew "hyperfine"' "$test_root/home/Projects/terminal-kit/Brewfile"
grep -Fq 'Usage: terminal-kit perf' "$test_root/home/Projects/terminal-kit/scripts/perf.sh"
grep -Fq 'perf         Benchmark and profile shell and cmux performance' "$test_root/home/Projects/terminal-kit/bin/terminal-kit"
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
grep -Fq '"showCustomMetadata": true' "$test_root/home/.config/cmux/cmux.json"
grep -Fq "$test_root/home/Projects/terminal-kit/config/zsh/init.zsh" "$test_root/home/.zshrc"
grep -Fq "$test_root/home/Projects/terminal-kit/config/tmux/tmux.conf" "$test_root/home/.tmux.conf"
cmp -s \
  "$test_root/home/Projects/terminal-kit/config/cmux/cmux.json.example" \
  "$test_root/home/.config/cmux/cmux.json"
cmp -s \
  "$test_root/home/Projects/terminal-kit/config/cmux/dock.json.example" \
  "$test_root/home/.config/cmux/dock.json"
[[ "$(HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" path)" == "$test_root/home/Projects/terminal-kit" ]]
HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" keys | grep -Fq 'tk keys Cheat sheet'
HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" perf status | grep -Fq 'terminal-kit performance settings'

printf 'terminal-kit tests passed\n'
