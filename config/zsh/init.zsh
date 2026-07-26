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

# Remove export attributes applied by older revisions so new cmux workspaces
# load their own helper and highlighting hooks.
typeset +x TERMINAL_KIT_HELPERS_LOADED 2>/dev/null || true
typeset +x TERMINAL_KIT_HIGHLIGHTING_LOADED 2>/dev/null || true

# Delta adds restrained syntax and word-level highlighting to Git diffs while
# preserving ordinary Git commands and paging behaviour.
if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER='delta --dark --navigate'
fi

# Keep tk refreshing the complete bootstrap rather than only the legacy file.
terminal-update() {
  command terminal-kit update "$@" || return
  local _terminal_kit_root
  _terminal_kit_root="$(command terminal-kit path)" || return
  source "$_terminal_kit_root/config/zsh/init.zsh"
  unset _terminal_kit_root
}
alias tk='terminal-update'

unset _terminal_kit_zsh_dir
