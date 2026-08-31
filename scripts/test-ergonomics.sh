#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/bin" "$test_root/repo" "$test_root/backups"

cat > "$test_root/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_GH_LOG"
if [[ "${1:-}" == config && "${2:-}" == get ]]; then
  printf 'ssh\n'
fi
FAKE_GH

cat > "$test_root/bin/micro" <<'FAKE_MICRO'
#!/usr/bin/env bash
exit 0
FAKE_MICRO

cat > "$test_root/bin/pbcopy" <<'FAKE_PBCOPY'
#!/usr/bin/env bash
cat > "$TEST_CLIPBOARD"
FAKE_PBCOPY

chmod +x "$test_root/bin/gh" "$test_root/bin/micro" "$test_root/bin/pbcopy"
export HOME="$test_root/home"
export PATH="$test_root/bin:/usr/bin:/bin"
export TEST_GH_LOG="$test_root/gh.log"
export TEST_CLIPBOARD="$test_root/clipboard"

# The saved GitHub preference defaults to SSH, while explicit URLs retain their
# transport. Seed the old global rewrite and prove both current modes remove it.
git config --global url.git@github.com:.insteadOf https://github.com/
/bin/bash "$ROOT/scripts/git.sh" ssh >/dev/null
if git config --global --get-all 'url.git@github.com:.insteadOf' 2>/dev/null | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: legacy HTTPS rewrite survived ssh mode\n' >&2
  exit 1
fi
grep -Fq 'config set git_protocol ssh --host github.com' "$TEST_GH_LOG"
grep -Fxq 'ssh' "$HOME/.config/terminal-kit/git-protocol"
explicit_https='https://github.com/example/project.git'
[[ "$(git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]]

/bin/bash "$ROOT/scripts/git.sh" https >/dev/null
if git config --global --get-all 'url.git@github.com:.insteadOf' 2>/dev/null | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: legacy HTTPS rewrite survived https mode\n' >&2
  exit 1
fi
grep -Fq 'config set git_protocol https --host github.com' "$TEST_GH_LOG"
grep -Fxq 'https' "$HOME/.config/terminal-kit/git-protocol"
[[ "$(git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]]

/bin/bash "$ROOT/scripts/git.sh" ssh >/dev/null
if git config --global --get-all 'url.git@github.com:.insteadOf' 2>/dev/null | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: legacy HTTPS rewrite returned after ssh mode\n' >&2
  exit 1
fi
[[ "$(git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]]

# Legacy/default terminal editor choices migrate to micro while custom choices stay intact.
editor_values="$(
  EDITOR=nano VISUAL=vim GIT_EDITOR=vi GH_EDITOR='' SUDO_EDITOR=/usr/bin/nano \
    /bin/zsh -c "source '$ROOT/config/zsh/env.zsh'; printf '%s|%s|%s|%s|%s' \"\$EDITOR\" \"\$VISUAL\" \"\$GIT_EDITOR\" \"\$GH_EDITOR\" \"\$SUDO_EDITOR\""
)"
[[ "$editor_values" == 'micro|micro|micro|micro|micro' ]]
custom_editor="$(EDITOR=helix /bin/zsh -c "source '$ROOT/config/zsh/env.zsh'; printf '%s' \"\$EDITOR\"")"
[[ "$custom_editor" == helix ]]

# `clip remote` stays reusable for Git; `clip web` is the browser form.
git -C "$test_root/repo" init -q
git -C "$test_root/repo" remote add origin git@github.com:example/project.git
/bin/zsh -c "cd '$test_root/repo'; source '$ROOT/config/zsh/tools.zsh'; clip remote >/dev/null"
[[ "$(cat "$TEST_CLIPBOARD")" == 'git@github.com:example/project.git' ]]
/bin/zsh -c "cd '$test_root/repo'; source '$ROOT/config/zsh/tools.zsh'; clip web >/dev/null"
[[ "$(cat "$TEST_CLIPBOARD")" == 'https://github.com/example/project' ]]

# A persisted activation under /tmp is guaranteed to go stale across reboots. The
# repair removes only that narrow source/dot-command form and preserves ordinary
# startup lines.
cat > "$HOME/.zshrc" <<'EOF_ZSHRC'
export KEEP_ME=yes
. /tmp/quarry-pr436-uv-bin/env
source '/tmp/another-tool/env'
source "$HOME/.local/env"
EOF_ZSHRC
export BACKUP_DIR="$test_root/backups"
source "$ROOT/scripts/lib.sh"
prune_ephemeral_zsh_sources "$HOME/.zshrc" >/dev/null
grep -Fxq 'export KEEP_ME=yes' "$HOME/.zshrc"
grep -Fq 'source "$HOME/.local/env"' "$HOME/.zshrc"
if grep -Fq '/tmp/' "$HOME/.zshrc"; then
  printf 'terminal-kit: temporary zsh source survived cleanup\n' >&2
  exit 1
fi
[[ -n "$(find "$test_root/backups" -type f -print -quit)" ]]

grep -Fq 'brew "micro"' "$ROOT/Brewfile"
grep -Fq "export DELTA_PAGER='less -FRX'" "$ROOT/config/zsh/init.zsh"
grep -Fq 'SSH is the default preference, explicit URLs keep their protocol, and browser/API links use HTTPS.' "$ROOT/AGENTS.md"
grep -Fq 'Keep `tk do` and ordinary human commands low-ceremony; agent-facing JSON and receipts may be richer.' "$ROOT/AGENTS.md"
grep -Fq 'Exact GitHub handoff should prefer `gh ... --json ... --jq ...` or `--template`' "$ROOT/AGENTS.md"

printf 'terminal-kit: Git transport, editor, pager, and startup repair checks passed\n'
