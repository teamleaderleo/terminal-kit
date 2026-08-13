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
  unset TERMINAL_KIT_HINT_ACTIVE
  unset TERMINAL_KIT_HINT_WORKSPACE
fi

typeset -g TERMINAL_KIT_SHELL_PID="$$"
typeset +x TERMINAL_KIT_SHELL_PID 2>/dev/null || true

# Let an existing Zsh framework keep ownership of completion. Plain terminal-kit
# shells use the existing compdump on ordinary launches and do a full discovery
# pass only when the dump is missing or older than a day. This avoids repeating
# compinit's directory/security scan on every new terminal while still picking up
# newly installed completions automatically.
if (( ! $+_comps )); then
  autoload -Uz compinit
  _terminal_kit_compdump="${ZDOTDIR:-$HOME}/.zcompdump"
  typeset -a _terminal_kit_stale_compdump
  _terminal_kit_stale_compdump=(${~_terminal_kit_compdump}(N.mh+24))
  if [[ -s "$_terminal_kit_compdump" ]] && (( ${#_terminal_kit_stale_compdump} == 0 )); then
    compinit -C -d "$_terminal_kit_compdump"
  else
    compinit -i -d "$_terminal_kit_compdump"
  fi
  unset _terminal_kit_compdump _terminal_kit_stale_compdump
fi

if command -v zoxide >/dev/null 2>&1; then
  if [[ -z "${TERMINAL_KIT_ZOXIDE_LOADED:-}" ]]; then
    typeset -g TERMINAL_KIT_ZOXIDE_LOADED=1
    typeset +x TERMINAL_KIT_ZOXIDE_LOADED 2>/dev/null || true
    eval "$(zoxide init zsh)"
  fi
fi

source "$_terminal_kit_zsh_dir/tools.zsh"

# The default prompt shows only the directory and prompt character. A local mode
# can opt into Git branch/status details or disable Starship entirely.
_terminal_kit_prompt_state="minimal"
if [[ -r "$HOME/.config/terminal-kit/prompt" ]]; then
  IFS= read -r _terminal_kit_prompt_state < "$HOME/.config/terminal-kit/prompt" || true
  _terminal_kit_prompt_state="${_terminal_kit_prompt_state//[[:space:]]/}"
fi
[[ "$_terminal_kit_prompt_state" == "on" ]] && _terminal_kit_prompt_state="minimal"
_terminal_kit_starship_config="$_terminal_kit_zsh_dir/../starship/terminal-kit.toml"
[[ "$_terminal_kit_prompt_state" == "detailed" ]] \
  && _terminal_kit_starship_config="$_terminal_kit_zsh_dir/../starship/detailed.toml"

if [[ "$_terminal_kit_prompt_state" != "off" ]] \
  && command -v starship >/dev/null 2>&1 \
  && [[ -z "${TERMINAL_KIT_STARSHIP_LOADED:-}" ]]; then
  typeset -g TERMINAL_KIT_STARSHIP_LOADED=1
  typeset +x TERMINAL_KIT_STARSHIP_LOADED 2>/dev/null || true
  export STARSHIP_CONFIG="$_terminal_kit_starship_config"
  eval "$(starship init zsh)"
fi

# terminal.zsh defines all ZLE widgets and deliberately loads syntax highlighting
# at its end. Keep it after Starship so highlighting remains the final widget wrapper.
source "$_terminal_kit_zsh_dir/terminal.zsh"

# terminal.zsh registers the title hooks. Cache the Git-derived project title by
# working directory so precmd can restore titles after child programs without
# spawning `git rev-parse` after every command. chpwd naturally refreshes the cache.
typeset -g _TERMINAL_KIT_PROJECT_TITLE_PWD=''
typeset -g _TERMINAL_KIT_PROJECT_TITLE=''
_terminal_kit_project_title() {
  local title root
  if [[ "$_TERMINAL_KIT_PROJECT_TITLE_PWD" != "$PWD" || -z "$_TERMINAL_KIT_PROJECT_TITLE" ]]; then
    if [[ "$PWD" == "$HOME" ]]; then
      title='~'
    elif root="$(command git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
      title="${root:t}"
    else
      title="${PWD:t}"
      [[ -n "$title" ]] || title='/'
    fi

    title="${title//$'\e'/}"
    title="${title//$'\a'/}"
    title="${title//$'\n'/ }"
    typeset -g _TERMINAL_KIT_PROJECT_TITLE_PWD="$PWD"
    typeset -g _TERMINAL_KIT_PROJECT_TITLE="$title"
  fi
  printf '\e]2;%s\a' "$_TERMINAL_KIT_PROJECT_TITLE"
}
_terminal_kit_project_title

source "$_terminal_kit_zsh_dir/highlight.zsh"

# Optional fresh-surface hints remain available, but are disabled by default because
# late sidebar metadata changes row height after the workspace has already appeared.
source "$_terminal_kit_zsh_dir/hints.zsh"

# Remove export attributes applied by older revisions so new cmux workspaces
# load their own helper, prompt, highlighting, and hint hooks.
typeset +x TERMINAL_KIT_HELPERS_LOADED 2>/dev/null || true
typeset +x TERMINAL_KIT_HIGHLIGHTING_LOADED 2>/dev/null || true
typeset +x TERMINAL_KIT_STARSHIP_LOADED 2>/dev/null || true
typeset +x TERMINAL_KIT_HINT_ACTIVE TERMINAL_KIT_HINT_WORKSPACE 2>/dev/null || true

# bat's base16 theme uses the terminal ANSI palette, so files and Markdown adapt
# when cmux rotates themes. Respect an explicit user choice when one already exists.
if [[ -z "${BAT_THEME:-}" ]]; then
  export BAT_THEME=base16
fi

# Delta uses BAT_THEME for syntax colours and can detect the terminal background.
# Short diffs should simply print and return to the prompt. Longer diffs remain in
# less, where `q` exits; -X leaves the viewed text visible in terminal scrollback.
if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER='delta --navigate --keep-plus-minus-markers'
  if [[ -z "${DELTA_PAGER:-}" ]]; then
    export DELTA_PAGER='less -FRX'
  fi
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

unset _terminal_kit_prompt_state _terminal_kit_starship_config _terminal_kit_zsh_dir
