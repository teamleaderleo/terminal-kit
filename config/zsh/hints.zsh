# terminal-kit: temporary cmux sidebar hints for fresh terminal surfaces.

[[ -o interactive ]] || return 0
[[ -n "${CMUX_WORKSPACE_ID:-}" ]] || return 0
command -v cmux >/dev/null 2>&1 || return 0
[[ -z "${TERMINAL_KIT_HINT_ACTIVE:-}" ]] || return 0

_terminal_kit_hint_state="on"
if [[ -r "$HOME/.config/terminal-kit/hints" ]]; then
  _terminal_kit_hint_state="$(tr -d '[:space:]' < "$HOME/.config/terminal-kit/hints")"
fi
[[ "$_terminal_kit_hint_state" == "on" ]] || {
  unset _terminal_kit_hint_state
  return 0
}

_terminal_kit_hint_file="${${(%):-%N}:A:h}/../hints.txt"
[[ -r "$_terminal_kit_hint_file" ]] || {
  unset _terminal_kit_hint_state _terminal_kit_hint_file
  return 0
}

typeset -a _terminal_kit_hints
_terminal_kit_hints=("${(@f)$(<"$_terminal_kit_hint_file")}")
(( ${#_terminal_kit_hints} > 0 )) || {
  unset _terminal_kit_hint_state _terminal_kit_hint_file _terminal_kit_hints
  return 0
}

_terminal_kit_hint_state_dir="$HOME/.config/terminal-kit"
_terminal_kit_hint_index_file="$_terminal_kit_hint_state_dir/hint-index"
_terminal_kit_hint_index=0
if [[ -r "$_terminal_kit_hint_index_file" ]]; then
  _terminal_kit_hint_index="$(tr -d '[:space:]' < "$_terminal_kit_hint_index_file")"
fi
[[ "$_terminal_kit_hint_index" == <-> ]] || _terminal_kit_hint_index=0
_terminal_kit_hint_index=$(( (_terminal_kit_hint_index % ${#_terminal_kit_hints}) + 1 ))
mkdir -p "$_terminal_kit_hint_state_dir"
print -r -- "$_terminal_kit_hint_index" > "$_terminal_kit_hint_index_file"
_terminal_kit_hint="${_terminal_kit_hints[$_terminal_kit_hint_index]}"

if command cmux set-status terminal-kit-hint "$_terminal_kit_hint" \
  --workspace "$CMUX_WORKSPACE_ID" --priority 1 >/dev/null 2>&1; then
  typeset -g TERMINAL_KIT_HINT_ACTIVE=1
  typeset -g TERMINAL_KIT_HINT_WORKSPACE="$CMUX_WORKSPACE_ID"
  typeset +x TERMINAL_KIT_HINT_ACTIVE TERMINAL_KIT_HINT_WORKSPACE 2>/dev/null || true

  autoload -Uz add-zsh-hook
  _terminal_kit_clear_sidebar_hint() {
    if command -v cmux >/dev/null 2>&1 && [[ -n "${TERMINAL_KIT_HINT_WORKSPACE:-}" ]]; then
      command cmux clear-status terminal-kit-hint \
        --workspace "$TERMINAL_KIT_HINT_WORKSPACE" >/dev/null 2>&1 || true
    fi
    add-zsh-hook -d preexec _terminal_kit_clear_sidebar_hint
    unset TERMINAL_KIT_HINT_ACTIVE TERMINAL_KIT_HINT_WORKSPACE
  }
  add-zsh-hook preexec _terminal_kit_clear_sidebar_hint
fi

unset _terminal_kit_hint_state _terminal_kit_hint_file _terminal_kit_hints
unset _terminal_kit_hint_state_dir _terminal_kit_hint_index_file
unset _terminal_kit_hint_index _terminal_kit_hint
