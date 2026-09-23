#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v zsh >/dev/null || { printf 'SKIP shell helpers: zsh unavailable\n'; exit 0; }
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/home"
for tool in pbcopy yazi cmux osascript git; do
  cat > "$test_root/bin/$tool" <<'STUB'
#!/bin/sh
case "${0##*/}" in
  pbcopy) cat > "$CLIPBOARD_LOG"; exit "${COPY_RESULT:-0}" ;;
  git) printf '%s\n' "$TEST_REMOTE" ;;
  yazi)
    for arg do
      case "$arg" in --cwd-file=*) printf '%s' "${arg#--cwd-file=}" > "$YAZI_TEMP_LOG" ;; esac
    done
    exit 23 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$test_root/bin/$tool"
done
export ROOT
HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" CLIPBOARD_LOG="$test_root/clipboard" YAZI_TEMP_LOG="$test_root/yazi-temp" zsh -f <<'ZSH'
source "$ROOT/config/zsh/tools.zsh"
check_result() {
  local expected=$1 result=0
  shift
  "$@" > "$HOME/result" || result=$?
  [[ $result == $expected ]] || { print -u2 -- "expected $expected, got $result: $*"; exit 1; }
}
check_result 0 after /usr/bin/true
check_result 1 after /usr/bin/false
check_result 17 after /bin/sh -c 'exit 17'
check_result 0 clip hello
# Cover each supported origin syntax and preserve the transport for clip remote.
for remote in git@github.com:example/project.git ssh://git@github.com/example/project.git https://github.com/example/project.git; do
  export TEST_REMOTE="$remote"
  check_result 0 clip web
  [[ "$(< "$CLIPBOARD_LOG")" == https://github.com/example/project ]] || exit 1
  check_result 0 clip remote
  [[ "$(< "$CLIPBOARD_LOG")" == "$remote" ]] || exit 1
done
export COPY_RESULT=19
check_result 19 clip hello
[[ ! -s "$HOME/result" ]] || exit 1
print content > "$HOME/input"
check_result 19 clip "$HOME/input"
[[ ! -s "$HOME/result" ]] || exit 1
check_result 19 clip < "$HOME/input"
[[ ! -s "$HOME/result" ]] || exit 1
before=$PWD
check_result 23 y
[[ $PWD == $before && ! -e "$(< "$YAZI_TEMP_LOG")" ]] || exit 1
ZSH
printf 'terminal-kit shell helper failure paths passed\n'
