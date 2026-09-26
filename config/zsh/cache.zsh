# terminal-kit: cached `tool init` scripts.
#
# fzf, atuin, zoxide and Starship print static shell code for a given binary.
# Forking each of them cost 0.5-2.4 s per new shell on a loaded machine, so keep
# their output keyed by the resolved binary and arguments. An upgrade resolves
# to a new Cellar path (or a newer file) and regenerates the cache.
#
# Usage: _terminal_kit_cached_init <command> [args...] && source "$REPLY"
# Callers source at their own scope so the init code's globals stay global.
(( $+functions[_terminal_kit_cached_init] )) || _terminal_kit_cached_init() {
  local bin="${commands[$1]:A}" dir="${XDG_CACHE_HOME:-$HOME/.cache}/terminal-kit/init" key
  [[ -n "$bin" ]] || return 1
  key="${bin//[^[:alnum:].-]/_}--${${(j: :)@[2,-1]}//[^[:alnum:].-]/_}"
  REPLY="$dir/$key.zsh"
  [[ -s "$REPLY" && ! "$bin" -nt "$REPLY" ]] && return 0
  mkdir -p "$dir" 2>/dev/null || return 1
  # Write then rename so concurrently restored terminals never source a partial file.
  if "$bin" "${@[2,-1]}" >| "$REPLY.$$" 2>/dev/null && [[ -s "$REPLY.$$" ]]; then
    command mv -f "$REPLY.$$" "$REPLY"
  else
    command rm -f "$REPLY.$$"
    return 1
  fi
}
