#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in "$ROOT/install.sh" "$ROOT/bin/terminal-kit" "$ROOT/scripts/"*.sh; do
  bash -n "$file"
done

if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/config/zsh/terminal.zsh"
fi

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$ROOT/config/cmux/cmux.json.example" >/dev/null
fi

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
  "$test_root/home/.zshrc" \
  "$test_root/home/.tmux.conf" \
  "$test_root/home/.config/ghostty/config" \
  "$test_root/home/.config/cmux/cmux.json")"
HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
  "$test_root/home/Projects/terminal-kit/install.sh" --skip-tools >/dev/null
after="$(shasum \
  "$test_root/home/.zshrc" \
  "$test_root/home/.tmux.conf" \
  "$test_root/home/.config/ghostty/config" \
  "$test_root/home/.config/cmux/cmux.json")"

[[ "$before" == "$after" ]]
[[ "$(grep -c '^# >>> terminal-kit: zsh >>>$' "$test_root/home/.zshrc")" == 1 ]]
[[ "$(grep -c '^# >>> terminal-kit: tmux >>>$' "$test_root/home/.tmux.conf")" == 1 ]]
[[ "$(grep -c '^# >>> terminal-kit: ghostty >>>$' "$test_root/home/.config/ghostty/config")" == 1 ]]
grep -Fq "$test_root/home/Projects/terminal-kit/config/ghostty/config" "$test_root/home/.config/ghostty/config"
grep -Fq "$test_root/home/Projects/terminal-kit/config/ghostty/appearance" "$test_root/home/.config/ghostty/config"
grep -Fq "$test_root/home/Projects/terminal-kit/config/zsh/terminal.zsh" "$test_root/home/.zshrc"
grep -Fq "$test_root/home/Projects/terminal-kit/config/tmux/tmux.conf" "$test_root/home/.tmux.conf"
cmp -s \
  "$test_root/home/Projects/terminal-kit/config/cmux/cmux.json.example" \
  "$test_root/home/.config/cmux/cmux.json"
[[ "$(HOME="$test_root/home" "$test_root/home/.local/bin/terminal-kit" path)" == "$test_root/home/Projects/terminal-kit" ]]

printf 'terminal-kit tests passed\n'
