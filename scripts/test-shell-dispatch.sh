#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v zsh >/dev/null || { printf 'SKIP shell dispatch: zsh unavailable\n'; exit 0; }
zsh_bin="$(command -v zsh)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/home"
for tool in lsof terminal-kit; do
  cat > "$test_root/bin/$tool" <<'STUB'
#!/bin/sh
case "${0##*/}" in
  lsof)
    [ -z "${LSOF_OUTPUT:-}" ] || printf '%s\n' "$LSOF_OUTPUT"
    [ -z "${LSOF_ERROR:-}" ] || printf '%s\n' "$LSOF_ERROR" >&2
    exit "${LSOF_RESULT:-0}" ;;
  terminal-kit) printf '%s\n' "$@" > "$DISPATCH_LOG"; exit "${DISPATCH_RESULT:-0}" ;;
esac
STUB
  chmod +x "$test_root/bin/$tool"
done
export ROOT
export HOME="$test_root/home" ZDOTDIR="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin"
export DISPATCH_LOG="$test_root/dispatch" RESTART_LOG="$test_root/restart"
"$zsh_bin" -f <<'ZSH'
source "$ROOT/config/zsh/tools.zsh"
check_result() {
  local expected=$1 result=0
  shift
  "$@" > "$HOME/result" 2> "$HOME/errors" || result=$?
  [[ $result == $expected ]] || { print -u2 -- "expected $expected, got $result: $*"; exit 1; }
}
export LSOF_RESULT=1
check_result 0 ports
[[ "$(< "$HOME/result")" == 'no listening TCP ports' && ! -s "$HOME/errors" ]] || exit 1
check_result 0 ports 00080
[[ "$(< "$HOME/result")" == 'no listener on TCP port 80' ]] || exit 1
for port in '' 0 65536 -1 invalid 1.2 999999999999999999999999; do
  check_result 2 ports "$port"
  [[ ! -s "$HOME/result" ]] || exit 1
done
check_result 2 ports 80 ignored
export LSOF_ERROR='lsof: permission denied'
check_result 1 ports
[[ ! -s "$HOME/result" && "$(< "$HOME/errors")" == "$LSOF_ERROR" ]] || exit 1
export LSOF_RESULT=127 LSOF_ERROR='lsof: command not found'
check_result 127 ports
[[ ! -s "$HOME/result" ]] || exit 1
export LSOF_RESULT=0 LSOF_ERROR='lsof: warning'
export LSOF_OUTPUT=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nserver 42 user 3u IPv4 0 0t0 TCP 127.0.0.1:80 (LISTEN)\nserver 43 user 3u IPv6 0 0t0 TCP [::1]:443 (LISTEN)'
check_result 0 ports 80
[[ "$(< "$HOME/result")" == *127.0.0.1:80* && "$(< "$HOME/result")" != *443* ]] || exit 1
[[ "$(< "$HOME/errors")" == "$LSOF_ERROR" ]] || exit 1
export LSOF_RESULT=1 LSOF_ERROR=''
check_result 1 ports
[[ ! -s "$HOME/result" && -s "$HOME/errors" ]] || exit 1
# A parser failure is also an inspection failure, not an empty listener list.
awk() { print -u2 -- 'awk: fixture parser failure'; return 29; }
export LSOF_RESULT=0
check_result 29 ports
[[ ! -s "$HOME/result" && "$(< "$HOME/errors")" == 'awk: fixture parser failure' ]] || exit 1
ZSH
# Each entrypoint dispatches subcommands exactly once. Stub exec in the fixture
# so restart intent is verified without replacing or restarting any process.
for entrypoint in update terminal init; do
  for operation in default update apply install doctor rollback failure; do
    rm -f "$DISPATCH_LOG" "$RESTART_LOG"
    result=0
    ENTRYPOINT="$entrypoint" OPERATION="$operation" "$zsh_bin" -f > "$test_root/output" <<'ZSH' || result=$?
TERMINAL_KIT_SHELL_PID=$$
TERMINAL_KIT_HELPERS_LOADED=1
TERMINAL_KIT_HIGHLIGHTING_LOADED=1
TERMINAL_KIT_ZOXIDE_LOADED=1
TERMINAL_KIT_STARSHIP_LOADED=1
source "$ROOT/config/zsh/$ENTRYPOINT.zsh"
exec() { print -r -- "$*" > "$RESTART_LOG"; }
case "$OPERATION" in
  default) terminal-update ;;
  apply) terminal-update update --apply fixture-sha ;;
  failure) export DISPATCH_RESULT=17; terminal-update update --apply fixture-sha || exit $? ;;
  *) terminal-update "$OPERATION" ;;
esac
print -r -- 'returned to caller'
ZSH
    if [[ "$operation" == failure ]]; then
      [[ "$result" == 17 && ! -e "$RESTART_LOG" ]]
    elif [[ "$operation" != apply && "$operation" != install ]]; then
      [[ "$result" == 0 && ! -e "$RESTART_LOG" ]]
      grep -Fq 'returned to caller' "$test_root/output"
    else
      [[ "$result" == 0 && -e "$RESTART_LOG" ]]
      [[ "$(cat "$RESTART_LOG")" == zsh ]]
    fi
    expected="$operation"
    [[ "$operation" != default ]] || expected=update
    [[ "$operation" != apply && "$operation" != failure ]] || expected=$'update\n--apply\nfixture-sha'
    [[ "$(cat "$DISPATCH_LOG")" == "$expected" ]]
  done
done
printf 'terminal-kit ports and shell dispatch checks passed\n'
