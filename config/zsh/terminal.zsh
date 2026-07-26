# terminal-kit: Zsh line editing, history, and optional helpers.

bindkey -e
KEYTIMEOUT=1
WORDCHARS=''
autoload -Uz select-word-style
select-word-style bash

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

# Use the same restrained indigo selection colour as the terminal theme.
zle_highlight=(
  ${zle_highlight:#region:*}
  ${zle_highlight:#paste:*}
  'region:bg=#30364A,fg=#F4F6FB'
  'paste:none'
)

# Load interactive helpers once per shell. Re-sourcing this file still refreshes
# colours, widgets, aliases, and bindings below.
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

# -----------------------------------------------------------------------------
# Native-ish macOS editing inside the Zsh command buffer.
# -----------------------------------------------------------------------------

_terminal_kit_select_backward_char() {
  (( REGION_ACTIVE )) || zle set-mark-command
  zle backward-char
}
zle -N _terminal_kit_select_backward_char

_terminal_kit_select_forward_char() {
  (( REGION_ACTIVE )) || zle set-mark-command
  zle forward-char
}
zle -N _terminal_kit_select_forward_char

_terminal_kit_select_backward_word() {
  (( REGION_ACTIVE )) || zle set-mark-command
  zle backward-word
}
zle -N _terminal_kit_select_backward_word

_terminal_kit_select_forward_word() {
  (( REGION_ACTIVE )) || zle set-mark-command
  zle forward-word
}
zle -N _terminal_kit_select_forward_word

_terminal_kit_select_beginning_of_line() {
  (( REGION_ACTIVE )) || zle set-mark-command
  zle beginning-of-line
}
zle -N _terminal_kit_select_beginning_of_line

_terminal_kit_select_end_of_line() {
  (( REGION_ACTIVE )) || zle set-mark-command
  zle end-of-line
}
zle -N _terminal_kit_select_end_of_line

_terminal_kit_select_all() {
  MARK=0
  CURSOR=${#BUFFER}
  REGION_ACTIVE=1
}
zle -N _terminal_kit_select_all

_terminal_kit_copy_region() {
  (( REGION_ACTIVE )) || return 0
  zle copy-region-as-kill
  print -rn -- "$CUTBUFFER" | command pbcopy
  zle deactivate-region
}
zle -N _terminal_kit_copy_region

_terminal_kit_cut_region() {
  (( REGION_ACTIVE )) || return 0
  zle kill-region
  zle -f kill
  print -rn -- "$CUTBUFFER" | command pbcopy
}
zle -N _terminal_kit_cut_region

_terminal_kit_backward_delete_char_or_region() {
  if (( REGION_ACTIVE )); then
    zle kill-region
  else
    zle backward-delete-char
  fi
}
zle -N _terminal_kit_backward_delete_char_or_region

_terminal_kit_delete_char_or_region() {
  if (( REGION_ACTIVE )); then
    zle kill-region
  else
    zle delete-char
  fi
}
zle -N _terminal_kit_delete_char_or_region

_terminal_kit_backward_kill_word_or_region() {
  if (( REGION_ACTIVE )); then
    zle kill-region
  else
    zle backward-kill-word
  fi
}
zle -N _terminal_kit_backward_kill_word_or_region

_terminal_kit_kill_word_or_region() {
  if (( REGION_ACTIVE )); then
    zle kill-region
  else
    zle kill-word
  fi
}
zle -N _terminal_kit_kill_word_or_region

_terminal_kit_backward_kill_line_or_region() {
  if (( REGION_ACTIVE )); then
    zle kill-region
  else
    zle backward-kill-line
  fi
}
zle -N _terminal_kit_backward_kill_line_or_region

_terminal_kit_kill_line_or_region() {
  if (( REGION_ACTIVE )); then
    zle kill-region
  else
    zle kill-line
  fi
}
zle -N _terminal_kit_kill_line_or_region

# Typing over an active region replaces it, like a native text field.
_terminal_kit_self_insert_or_region() {
  (( REGION_ACTIVE )) && zle kill-region
  zle .self-insert
}
zle -N self-insert _terminal_kit_self_insert_or_region

# Plain movement collapses a selection to the appropriate edge.
_terminal_kit_collapse_region_left() {
  if (( REGION_ACTIVE )); then
    (( CURSOR > MARK )) && CURSOR=$MARK
    zle deactivate-region
  else
    zle backward-char
  fi
}
zle -N _terminal_kit_collapse_region_left

_terminal_kit_collapse_region_right() {
  if (( REGION_ACTIVE )); then
    (( CURSOR < MARK )) && CURSOR=$MARK
    zle deactivate-region
  else
    zle forward-char
  fi
}
zle -N _terminal_kit_collapse_region_right

_terminal_kit_beginning_or_collapse() {
  if (( REGION_ACTIVE )); then
    (( CURSOR > MARK )) && CURSOR=$MARK
    zle deactivate-region
  else
    zle beginning-of-line
  fi
}
zle -N _terminal_kit_beginning_or_collapse

_terminal_kit_end_or_collapse() {
  if (( REGION_ACTIVE )); then
    (( CURSOR < MARK )) && CURSOR=$MARK
    zle deactivate-region
  else
    zle end-of-line
  fi
}
zle -N _terminal_kit_end_or_collapse

_terminal_kit_backward_word_or_collapse() {
  if (( REGION_ACTIVE )); then
    (( CURSOR > MARK )) && CURSOR=$MARK
    zle deactivate-region
  else
    zle backward-word
  fi
}
zle -N _terminal_kit_backward_word_or_collapse

_terminal_kit_forward_word_or_collapse() {
  if (( REGION_ACTIVE )); then
    (( CURSOR < MARK )) && CURSOR=$MARK
    zle deactivate-region
  else
    zle forward-word
  fi
}
zle -N _terminal_kit_forward_word_or_collapse

_terminal_kit_up_or_deselect() {
  (( REGION_ACTIVE )) && zle deactivate-region
  zle up-line-or-history
}
zle -N _terminal_kit_up_or_deselect

_terminal_kit_down_or_deselect() {
  (( REGION_ACTIVE )) && zle deactivate-region
  zle down-line-or-history
}
zle -N _terminal_kit_down_or_deselect

# Command-key sequences sent by Ghostty and cmux.
bindkey '\e[25~' _terminal_kit_select_all
bindkey '\e[26~' _terminal_kit_copy_region
bindkey '\e[28~' _terminal_kit_cut_region
bindkey '\e[29~' undo
bindkey '\e[31~' redo

# Cmd+Left/Right and their Ctrl+A/Ctrl+E shell equivalents.
bindkey '^A' _terminal_kit_beginning_or_collapse
bindkey '^E' _terminal_kit_end_or_collapse

# Shift+Arrow, Option+Shift+Arrow, and Cmd+Shift+Arrow selection.
bindkey '\e[1;2D' _terminal_kit_select_backward_char
bindkey '\e[1;2C' _terminal_kit_select_forward_char
bindkey '\e[1;4D' _terminal_kit_select_backward_word
bindkey '\e[1;4C' _terminal_kit_select_forward_word
bindkey '\e[1;2H' _terminal_kit_select_beginning_of_line
bindkey '\e[1;2F' _terminal_kit_select_end_of_line

# Plain arrows in normal and application cursor modes.
bindkey '\e[D' _terminal_kit_collapse_region_left
bindkey '\e[C' _terminal_kit_collapse_region_right
bindkey '\e[A' _terminal_kit_up_or_deselect
bindkey '\e[B' _terminal_kit_down_or_deselect
bindkey '\eOD' _terminal_kit_collapse_region_left
bindkey '\eOC' _terminal_kit_collapse_region_right
bindkey '\eOA' _terminal_kit_up_or_deselect
bindkey '\eOB' _terminal_kit_down_or_deselect

# Option+Left/Right plus CSI fallbacks used by other terminals.
bindkey '\eb' _terminal_kit_backward_word_or_collapse
bindkey '\ef' _terminal_kit_forward_word_or_collapse
bindkey '\e[1;3D' _terminal_kit_backward_word_or_collapse
bindkey '\e[1;3C' _terminal_kit_forward_word_or_collapse

# Backspace/Delete and word/line deletion remove an active selection first.
bindkey '^?' _terminal_kit_backward_delete_char_or_region
bindkey '^H' _terminal_kit_backward_delete_char_or_region
bindkey '\e[3~' _terminal_kit_delete_char_or_region
bindkey '^W' _terminal_kit_backward_kill_word_or_region
bindkey '\ed' _terminal_kit_kill_word_or_region
bindkey '^U' _terminal_kit_backward_kill_line_or_region
bindkey '^K' _terminal_kit_kill_line_or_region

# Autosuggestions wraps ZLE widgets. Refresh its wrappers after redefining self-insert.
if (( $+functions[_zsh_autosuggest_bind_widgets] )); then
  _zsh_autosuggest_bind_widgets
fi

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
