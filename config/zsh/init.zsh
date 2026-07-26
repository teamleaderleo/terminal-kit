# terminal-kit: per-shell bootstrap for completions, helpers, and highlighting.

# Older versions exported these sentinels. A child shell inherited them and
# incorrectly assumed its own plugins were already loaded. Reset them once per
# shell process, then keep the replacement markers shell-local.
if [[ "${TERMINAL_KIT_SHELL_PID:-}" != "$$" ]]; then
  unset TERMINAL_KIT_HELPERS_LOADED
  unset TERMINAL_KIT_HIGHLIGHTING_LOADED
  unset TERMINAL_KIT_PRELUDE_LOADED
fi

typeset -g TERMINAL_KIT_SHELL_PID="$$"
typeset +x TERMINAL_KIT_SHELL_PID 2>/dev/null || true

# Completion setup and zoxide must run before zsh-syntax-highlighting, which is
# sourced at the end of terminal.zsh.
if [[ -z "${TERMINAL_KIT_PRELUDE_LOADED:-}" ]]; then
  typeset -g TERMINAL_KIT_PRELUDE_LOADED=1
  typeset +x TERMINAL_KIT_PRELUDE_LOADED 2>/dev/null || true

  for _terminal_kit_brew_prefix in /opt/homebrew /usr/local; do
    _terminal_kit_completion_dir="$_terminal_kit_brew_prefix/share/zsh-completions"
    if [[ -d "$_terminal_kit_completion_dir" ]] && (( ${fpath[(Ie)$_terminal_kit_completion_dir]} == 0 )); then
      fpath=("$_terminal_kit_completion_dir" $fpath)
    fi
  done

  autoload -Uz compinit
  if [[ -z "${_comps+x}" ]]; then
    compinit -d "$HOME/.zcompdump"
  fi
  zstyle ':completion:*' menu select
  zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

  if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
  fi

  unset _terminal_kit_brew_prefix _terminal_kit_completion_dir
fi

_terminal_kit_zsh_dir="${${(%):-%N}:A:h}"
source "$_terminal_kit_zsh_dir/terminal.zsh"

# Remove the export attribute applied by older terminal.zsh revisions so new
# cmux workspaces load their own helper and highlighting hooks.
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
