#!/usr/bin/env bash
set -euo pipefail
# bash 3.2 (macOS /bin/bash) ignores set -e for a failing [[ ]]; assert explicitly.
fail_at() { printf '%s: assertion failed at line %s\n' "${0##*/}" "$1" >&2; exit 1; }

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

# The saved GitHub preference defaults to SSH, while explicit Git URLs keep the
# protocol they name. Also prove current transport setup removes the old global
# HTTPS-to-SSH rewrite from earlier terminal-kit versions.
git config --global url.git@github.com:.insteadOf https://github.com/
/bin/bash "$ROOT/scripts/git.sh" ssh >/dev/null
if git config --global --get-all 'url.git@github.com:.insteadOf' 2>/dev/null \
  | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: legacy HTTPS rewrite survived ssh mode\n' >&2
  exit 1
fi
grep -Fq 'config set git_protocol ssh --host github.com' "$TEST_GH_LOG"
grep -Fxq 'ssh' "$HOME/.config/terminal-kit/git-protocol"
explicit_https='https://github.com/example/project.git'
[[ "$(git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]] || fail_at $LINENO

/bin/bash "$ROOT/scripts/git.sh" https >/dev/null
if git config --global --get-all 'url.git@github.com:.insteadOf' 2>/dev/null \
  | grep -Fxq 'https://github.com/'; then
  printf 'terminal-kit: legacy HTTPS rewrite survived https mode\n' >&2
  exit 1
fi
grep -Fq 'config set git_protocol https --host github.com' "$TEST_GH_LOG"
grep -Fxq 'https' "$HOME/.config/terminal-kit/git-protocol"
[[ "$(git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]] || fail_at $LINENO
/bin/bash "$ROOT/scripts/git.sh" ssh >/dev/null
grep -Fxq 'ssh' "$HOME/.config/terminal-kit/git-protocol"
[[ "$(git ls-remote --get-url "$explicit_https")" == "$explicit_https" ]] || fail_at $LINENO

# Legacy/default terminal editor choices migrate to micro while custom choices stay intact.
editor_values="$(
  EDITOR=nano VISUAL=vim GIT_EDITOR=vi GH_EDITOR='' SUDO_EDITOR=/usr/bin/nano \
    /bin/zsh -c "source '$ROOT/config/zsh/env.zsh'; printf '%s|%s|%s|%s|%s' \"\$EDITOR\" \"\$VISUAL\" \"\$GIT_EDITOR\" \"\$GH_EDITOR\" \"\$SUDO_EDITOR\""
)"
[[ "$editor_values" == 'micro|micro|micro|micro|micro' ]] || fail_at $LINENO
custom_editor="$(EDITOR=helix /bin/zsh -c "source '$ROOT/config/zsh/env.zsh'; printf '%s' \"\$EDITOR\"")"
[[ "$custom_editor" == helix ]] || fail_at $LINENO

# `clip remote` stays reusable for Git; `clip web` is the browser form.
git -C "$test_root/repo" init -q
git -C "$test_root/repo" remote add origin git@github.com:example/project.git
/bin/zsh -c "cd '$test_root/repo'; source '$ROOT/config/zsh/tools.zsh'; clip remote >/dev/null"
[[ "$(cat "$TEST_CLIPBOARD")" == 'git@github.com:example/project.git' ]] || fail_at $LINENO
/bin/zsh -c "cd '$test_root/repo'; source '$ROOT/config/zsh/tools.zsh'; clip web >/dev/null"
[[ "$(cat "$TEST_CLIPBOARD")" == 'https://github.com/example/project' ]] || fail_at $LINENO

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
[[ -n "$(find "$test_root/backups" -type f -print -quit)" ]] || fail_at $LINENO

# A begin marker without its end marker must not swallow the rest of the file.
managed="$HOME/managed.conf"
printf 'keep-before\n# >>> terminal-kit: demo >>>\nold-body\nkeep-after-1\nkeep-after-2\n' > "$managed"
printf 'new-body\n' | replace_managed_block "$managed" demo
grep -Fxq keep-before "$managed"
grep -Fxq keep-after-1 "$managed"
grep -Fxq keep-after-2 "$managed"
grep -Fxq new-body "$managed"
[[ "$(grep -c '^# >>> terminal-kit: demo >>>$' "$managed")" == 1 ]] || fail_at $LINENO
[[ "$(grep -c '^# <<< terminal-kit: demo <<<$' "$managed")" == 1 ]] || fail_at $LINENO
# A complete block is replaced in place and re-running changes nothing.
printf 'newer-body\n' | replace_managed_block "$managed" demo
if grep -Fxq new-body "$managed"; then fail_at $LINENO; fi
managed_sum="$(shasum "$managed")"
printf 'newer-body\n' | replace_managed_block "$managed" demo
[[ "$(shasum "$managed")" == "$managed_sum" ]] || fail_at $LINENO
remove_managed_block "$managed" demo
if grep -Fq 'terminal-kit: demo' "$managed"; then fail_at $LINENO; fi
grep -Fxq keep-after-2 "$managed"

# Only the newest backup directories are kept.
mkdir -p "$HOME/.config/terminal-kit-backups"
for stamp in 20260101-000001 20260101-000002 20260101-000003 20260101-000004-karabiner; do
  mkdir -p "$HOME/.config/terminal-kit-backups/$stamp"
done
prune_backups 2
[[ "$(ls "$HOME/.config/terminal-kit-backups" | tr '\n' ' ')" == '20260101-000003 20260101-000004-karabiner ' ]] || fail_at $LINENO

printf 'terminal-kit: Git transport, editor, pager, and startup repair checks passed\n'
