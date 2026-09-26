#!/usr/bin/env bash
set -euo pipefail

# Drive the real Zsh line editor through a pseudo-terminal and record every
# pbcopy call, so clipboard writes are checked by behaviour rather than by text.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/zdot"

cat > "$test_root/bin/pbcopy" <<'FAKE_PBCOPY'
#!/bin/sh
printf 'pbcopy[%s]\n' "$(cat)" >> "$TEST_LOG"
FAKE_PBCOPY
chmod +x "$test_root/bin/pbcopy"

cat > "$test_root/zdot/.zshrc" <<ZSHRC
PATH="$test_root/bin:\$PATH"
TERMINAL_KIT_HELPERS_LOADED=1
TERMINAL_KIT_HIGHLIGHTING_LOADED=1
source "$ROOT/config/zsh/terminal.zsh" 2>/dev/null
PS1='> '
# Stand-in for the copy helper: report what a child process can see.
unalias tk 2>/dev/null
tk() { /usr/bin/env | /usr/bin/grep '^TERMINAL_KIT_LAST_COMMAND=' >> "\$TEST_LOG" || print 'helper-env[unset]' >> "\$TEST_LOG"; }
ZSHRC

cat > "$test_root/drive.zsh" <<'DRIVE'
zmodload zsh/zpty
zpty z "ZDOTDIR=$TEST_ZDOT TERM=xterm-256color zsh -i"
keys() { zpty -w -n z "$1"; sleep 0.2 }
# Discard the edited line, log a marker from inside the shell, and wait for it.
mark() {
  local out
  zpty -w -n z $'\C-g'
  zpty -w -n z "print -r -- $1 >> \$TEST_LOG; print DO\"\"NE"$'\r'
  zpty -r z out '*DONE*'
}
mark start

# Select-all on an empty prompt, then copy: the clipboard must stay untouched.
keys $'\C-x\C-a'; keys $'\ew'; mark empty-select-all

# Shift-selecting nothing (left then right) and copying must not write either.
keys 'abc'; keys $'\e[1;2D'; keys $'\e[1;2C'; keys $'\ew'; mark zero-width

# A real selection copies exactly the selected text.
keys 'echo hi'; keys $'\C-x\C-a'; keys $'\ew'; mark full-line

# Private Cmd-key sequences from old Ghostty configs no longer copy anything.
keys 'secret'; keys $'\C-x\C-a'; keys $'\e[26~'; mark legacy-sequence

# The last command reaches `tk copy command` but no other child process.
keys $'/usr/bin/env | /usr/bin/grep -c ^TERMINAL_KIT_LAST_COMMAND= >> $TEST_LOG\r'
keys $'tk copy command\r'
mark end
zpty -d z
DRIVE

export TEST_LOG="$test_root/log" TEST_ZDOT="$test_root/zdot"
: > "$TEST_LOG"
perl -e 'alarm 60; exec @ARGV' zsh -f "$test_root/drive.zsh" >/dev/null 2>&1

expected='start
empty-select-all
zero-width
pbcopy[echo hi]
full-line
legacy-sequence
0
TERMINAL_KIT_LAST_COMMAND=/usr/bin/env | /usr/bin/grep -c ^TERMINAL_KIT_LAST_COMMAND= >> $TEST_LOG
end'

if [[ "$(cat "$TEST_LOG")" != "$expected" ]]; then
  printf 'terminal-kit prompt clipboard test failed; got:\n' >&2
  cat "$TEST_LOG" >&2
  exit 1
fi

printf 'terminal-kit prompt clipboard tests passed\n'
