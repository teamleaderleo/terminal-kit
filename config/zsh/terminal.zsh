# terminal-kit: Zsh line editing, history, and optional helpers.

bindkey -e
KEYTIMEOUT=1
WORDCHARS=''

# Persistent history shared across interactive shells.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_FIND_NO_DUPS

# Load interactive helpers once per shell. Re-sourcing this file still refreshes
# all key bindings below.
if [[ -z "${TERMINAL_KIT_HELPERS_LOADED:-}" ]]; then
  export TERMINAL_KIT_HELPERS_LOADED=1

  if command -v fzf >/dev/null 2>&1; then
    source <(fzf --zsh)
  fi

  if command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init zsh --disable-up-arrow)"
  fi

  for _terminal_kit_brew_prefix in /opt/homebrew /usr/local; do
    if [[ -r "$_terminal_kit_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
      source "$_terminal_kit_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
      break
    fi
  done
  unset _terminal_kit_brew_prefix
fi

# Command-key sequences sent by Ghostty and cmux.
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^[b' backward-word
bindkey '^[f' forward-word
bindkey '^U' backward-kill-line
bindkey '^W' backward-kill-word
bindkey '^_' undo
bindkey '^[Z' redo

# One command updates the checkout, reloads apps, and refreshes this shell.
terminal-update() {
  command terminal-kit update "$@" || return
  local _terminal_kit_root
  _terminal_kit_root="$(command terminal-kit path)" || return
  source "$_terminal_kit_root/config/zsh/terminal.zsh"
  unset _terminal_kit_root
}
alias tk='terminal-update'

# Syntax highlighting stays last and loads once.
if [[ -z "${TERMINAL_KIT_HIGHLIGHTING_LOADED:-}" ]]; then
  export TERMINAL_KIT_HIGHLIGHTING_LOADED=1
  for _terminal_kit_brew_prefix in /opt/homebrew /usr/local; do
    if [[ -r "$_terminal_kit_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
      source "$_terminal_kit_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
      break
    fi
  done
  unset _terminal_kit_brew_prefix
fi
