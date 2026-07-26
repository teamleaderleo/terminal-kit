# terminal-kit: per-shell bootstrap for helpers and highlighting.

_terminal_kit_zsh_dir="${${(%):-%N}:A:h}"

# Also load the baseline here so `source init.zsh` repairs the current shell,
# even before the installer has added the ~/.zshenv include.
source "$_terminal_kit_zsh_dir/env.zsh"

# Older versions exported these sentinels. A child shell inherited them and
# incorrectly assumed its own plugins were already loaded. Reset them once per
# shell process, then keep the replacement markers shell-local.
if [[ "${TERMINAL_KIT_SHELL_PID:-}" != "$$" ]]; then
  unset TERMINAL_KIT_HELPERS_LOADED
  unset TERMINAL_KIT_HIGHLIGHTING_LOADED
fi

typeset -g TERMINAL_KIT_SHELL_PID="$$"
typeset +x TERMINAL_KIT_SHELL_PID 2>/dev/null || true

# Do not call compinit here. Existing frameworks, Bun, and other user startup
# files often own completion already; running it twice caused security prompts
# and half-initialised `compdef` state. terminal-kit stays out of that path.
if command -v zoxide >/dev/null 2>&1; then
  if [[ -z "${TERMINAL_KIT_ZOXIDE_LOADED:-}" ]]; then
    typeset -g TERMINAL_KIT_ZOXIDE_LOADED=1
    typeset +x TERMINAL_KIT_ZOXIDE_LOADED 2>/dev/null || true
    eval "$(zoxide init zsh)"
  fi
fi

source "$_terminal_kit_zsh_dir/terminal.zsh"
source "$_terminal_kit_zsh_dir/highlight.zsh"

# Remove export attributes applied by older revisions so new cmux workspaces
# load their own helper and highlighting hooks.
typeset +x TERMINAL_KIT_HELPERS_LOADED 2>/dev/null || true
typeset +x TERMINAL_KIT_HIGHLIGHTING_LOADED 2>/dev/null || true

# bat's base16 theme uses the terminal ANSI palette, so files and Markdown adapt
# when cmux rotates themes. Respect an explicit user choice when one already exists.
if [[ -z "${BAT_THEME:-}" ]]; then
  export BAT_THEME=base16
fi

# Delta uses BAT_THEME for syntax colours and can detect the terminal background.
if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER='delta --navigate'
fi

# `tk` with no arguments performs the normal update. Arguments dispatch directly
# to terminal-kit, so `tk theme next`, `tk doctor`, and similar commands work.
terminal-update() {
  if (( $# > 0 )); then
    command terminal-kit "$@"
    return
  fi

  command terminal-kit update || return
  local _terminal_kit_root
  _terminal_kit_root="$(command terminal-kit path)" || return
  source "$_terminal_kit_root/config/zsh/init.zsh"
  unset _terminal_kit_root
}
alias tk='terminal-update'

unset _terminal_kit_zsh_dir
