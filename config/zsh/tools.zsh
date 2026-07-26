# terminal-kit: small wrappers for modern terminal tools.

# Yazi's shell wrapper returns the directory selected when the TUI exits.
if command -v yazi >/dev/null 2>&1; then
  y() {
    local _terminal_kit_yazi_tmp _terminal_kit_yazi_cwd
    _terminal_kit_yazi_tmp="$(mktemp -t 'yazi-cwd.XXXXXX')" || return
    command yazi "$@" --cwd-file="$_terminal_kit_yazi_tmp"
    IFS= read -r -d '' _terminal_kit_yazi_cwd < "$_terminal_kit_yazi_tmp"
    if [[ -n "$_terminal_kit_yazi_cwd" && "$_terminal_kit_yazi_cwd" != "$PWD" && -d "$_terminal_kit_yazi_cwd" ]]; then
      builtin cd -- "$_terminal_kit_yazi_cwd"
    fi
    command rm -f -- "$_terminal_kit_yazi_tmp"
    unset _terminal_kit_yazi_tmp _terminal_kit_yazi_cwd
  }
fi

if command -v lazygit >/dev/null 2>&1; then
  alias lg='lazygit'
fi

if command -v btop >/dev/null 2>&1; then
  alias bt='btop'
fi

if command -v fd >/dev/null 2>&1; then
  alias findf='fd --hidden --exclude .git'
fi

# Ordinary terminal output should keep wrapping. `wide` is the deliberate escape
# hatch for long table rows, logs, source lines, and diffs. less -S keeps each
# input line on one row; Left/Right or horizontal trackpad gestures move sideways.
wide() {
  if (( $# > 0 )); then
    command less -R -S -- "$@"
  else
    command less -R -S
  fi
}
