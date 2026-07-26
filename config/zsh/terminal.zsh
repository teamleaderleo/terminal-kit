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

# Calm command-line colours. Keep ordinary typing close to the terminal foreground;
# reserve indigo for useful distinctions and dim comments/suggestions.
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#B9C0D4'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#9AA9D8'
ZSH_HIGHLIGHT_STYLES[command]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#AAB5D8'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[function]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[global-alias]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[path]='fg=#AEB8D7'
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=#8E99B9'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#9BA7C8'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#9BA7C8'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#C7CDDC'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#C7CDDC'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#C7CDDC'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#8792B0'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#A4AFD0'
ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#A4AFD0'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#656D82'
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#596074'

# Load interactive helpers once per shell. Re-sourcing this file still refreshes
# colours, aliases, and all key bindings below.
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

  # grc adds colour to selected traditional commands such as ping, make, diff,
  # ps, and traceroute without changing their underlying programs.
  for _terminal_kit_grc_file in /opt/homebrew/etc/grc.zsh /usr/local/etc/grc.zsh; do
    if [[ -r "$_terminal_kit_grc_file" ]]; then
      source "$_terminal_kit_grc_file"
      break
    fi
  done

  unset _terminal_kit_brew_prefix _terminal_kit_grc_file
fi

# Small, colour-aware replacements. These are interactive aliases only.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lah --group-directories-first --git --icons=auto'
  alias tree='eza --tree --icons=auto'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never --style=plain'
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

# One command updates the checkout, installs newly-added tools, reloads apps, and
# refreshes this shell.
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
