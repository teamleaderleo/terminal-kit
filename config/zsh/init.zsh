# terminal-kit: per-shell bootstrap for helpers, prompt, and highlighting.

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
  unset TERMINAL_KIT_STARSHIP_LOADED
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

source "$_terminal_kit_zsh_dir/tools.zsh"

# The compact Starship prompt is enabled by default, but a machine-local switch
# lets it be disabled without editing or dirtying the repository.
_terminal_kit_prompt_state="on"
if [[ -r "$HOME/.config/terminal-kit/prompt" ]]; then
  _terminal_kit_prompt_state="$(tr -d '[:space:]' < "$HOME/.config/terminal-kit/prompt")"
fi
if [[ "$_terminal_kit_prompt_state" != "off" ]] \
  && command -v starship >/dev/null 2>&1 \
  && [[ -z "${TERMINAL_KIT_STARSHIP_LOADED:-}" ]]; then
  typeset -g TERMINAL_KIT_STARSHIP_LOADED=1
  typeset +x TERMINAL_KIT_STARSHIP_LOADED 2>/dev/null || true
  export STARSHIP_CONFIG="$_terminal_kit_zsh_dir/../starship/terminal-kit.toml"
  eval "$(starship init zsh)"
fi

# terminal.zsh defines all ZLE widgets and deliberately loads syntax highlighting
# at its end. Keep it after Starship so highlighting remains the final widget wrapper.
source "$_terminal_kit_zsh_dir/terminal.zsh"
source "$_terminal_kit_zsh_dir/highlight.zsh"

# Remove export attributes applied by older revisions so new cmux workspaces
# load their own helper, prompt, and highlighting hooks.
typeset +x TERMINAL_KIT_HELPERS_LOADED 2>/dev/null || true
typeset +x TERMINAL_KIT_HIGHLIGHTING_LOADED 2>/dev/null || true
typeset +x TERMINAL_KIT_STARSHIP_LOADED 2>/dev/null || true

# bat's base16 theme uses the terminal ANSI palette, so files and Markdown adapt
# when cmux rotates themes. Respect an explicit user choice when one already exists.
if [[ -z "${BAT_THEME:-}" ]]; then
  export BAT_THEME=base16
fi

# Delta uses BAT_THEME for syntax colours and can detect the terminal background.
if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER='delta --navigate'
fi

# Plain `tk` and explicit `tk update` both update the kit. Updates replace the
# current shell process instead of sourcing the full bootstrap into an active
# prompt; this prevents duplicated prompts and stale cursor cells after Starship
# or ZLE changes. Other subcommands return to the existing shell normally.
terminal-update() {
  local _terminal_kit_command="${1:-update}"
  if (( $# == 0 )); then
    set -- update
  fi

  command terminal-kit "$@" || return
  case "$_terminal_kit_command" in
    update|install)
      exec zsh
      ;;
  esac
}
alias tk='terminal-update'

unset _terminal_kit_prompt_state _terminal_kit_zsh_dir