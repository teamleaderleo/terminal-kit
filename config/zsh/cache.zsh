# terminal-kit: cached `tool init` scripts.
#
# fzf, atuin, zoxide and Starship print shell code that only changes with the
# binary, a few environment variables, or a config file. Forking each of them
# cost 0.5-2.4 s per new shell on a loaded machine, so keep their output keyed
# by the resolved binary (path, size, mtime), its arguments and any listed
# environment variables, and regenerate when a listed dependency file is newer.
#
# Usage: _terminal_kit_cached_init [-e VAR]... [-d FILE]... <command> [args...]
# On success REPLY names the cached file. Callers source it at their own scope so
# the init code's globals stay global, and fall back to a live eval on failure
# (for example a read-only cache directory).
(( $+functions[_terminal_kit_cached_init] )) || _terminal_kit_cached_init() {
  local -a deps envs old
  local -A st
  while [[ "$1" == -[de] ]]; do
    [[ "$1" == -d ]] && deps+=("$2") || envs+=("$2=${(P)2}")
    shift 2
  done
  local name="$1" bin="${commands[$1]:A}" dir="${XDG_CACHE_HOME:-$HOME/.cache}/terminal-kit/init" key dep
  [[ -n "$bin" ]] || return 1
  zmodload -F zsh/stat b:zstat 2>/dev/null && zstat -H st "$bin" 2>/dev/null
  key="$name--$bin-$st[size]-$st[mtime]--${(j: :)@[2,-1]}--${(j: :)envs}"
  REPLY="$dir/${key//[^[:alnum:].=-]/_}.zsh"
  if [[ -s "$REPLY" ]]; then
    for dep in $deps; do [[ "$dep" -nt "$REPLY" ]] && break; done
    [[ "$dep" -nt "$REPLY" ]] || return 0
  fi
  # Write then rename so concurrently restored terminals never source a partial
  # file, then drop outputs cached for other versions of this tool.
  if {
    mkdir -p "$dir" && "$bin" "${@[2,-1]}" >| "$REPLY.$$" && [[ -s "$REPLY.$$" ]] \
      && command mv -f "$REPLY.$$" "$REPLY"
  } 2>/dev/null; then
    old=("$dir/$name--"*.zsh(N))
    old=(${old:#$REPLY})
    (( $#old )) && command rm -f -- $old 2>/dev/null
    return 0
  fi
  command rm -f -- "$REPLY.$$" 2>/dev/null
  return 1
}
