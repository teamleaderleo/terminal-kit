#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v zsh >/dev/null || { printf 'SKIP shell environment: zsh unavailable\n'; exit 0; }
zsh_bin="$(command -v zsh)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/tool chain/bin"
cat > "$test_root/tool chain/bin/python3" <<'STUB'
#!/bin/sh
printf 'activated-toolchain\n'
STUB
chmod +x "$test_root/tool chain/bin/python3"
printf 'source "$ROOT/config/zsh/env.zsh"\n' > "$test_root/home/.zshenv"
export ROOT
HOME="$test_root/home" ZDOTDIR="$test_root/home" TOOLCHAIN_BIN="$test_root/tool chain/bin" ZSH_BIN="$zsh_bin" "$zsh_bin" -f <<'ZSH'
set -e
# Model activation in the parent: a toolchain, followed by ordinary system paths.
path=("$TOOLCHAIN_BIN" /usr/bin /bin)
source "$ROOT/config/zsh/env.zsh"
[[ "$path[1]" == "$TOOLCHAIN_BIN" && "$path[2]" == /usr/bin && "$path[3]" == /bin ]]
[[ "$(python3)" == activated-toolchain ]]
first_path="$PATH"
source "$ROOT/config/zsh/env.zsh"
[[ "$PATH" == "$first_path" ]]
# The installed .zshenv runs in a child noninteractive shell without -f.
[[ "$("$ZSH_BIN" -c 'python3')" == activated-toolchain ]]
[[ "$("$ZSH_BIN" -c 'print -r -- "$PATH"')" == "$first_path" ]]
# Repair an incomplete PATH without displacing its first directory.
path=("$TOOLCHAIN_BIN")
source "$ROOT/config/zsh/env.zsh"
[[ "$path[1]" == "$TOOLCHAIN_BIN" ]]
for required in "$HOME/.local/bin" /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin /usr/local/sbin /usr/bin /bin /usr/sbin /sbin; do
  (( ${path[(Ie)$required]} > 0 ))
done
[[ "$(python3)" == activated-toolchain ]]
(( ${#path} == 10 ))
ZSH
printf 'terminal-kit shell environment precedence checks passed\n'
