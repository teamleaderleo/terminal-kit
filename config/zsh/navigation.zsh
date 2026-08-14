# terminal-kit: predictable project-directory jumps layered under normal Zsh `cd`.
#
# A single bare directory name first goes through Zsh's builtin unchanged. If that
# fails, resolve an exact direct child of the configured project roots. This makes
# history/autosuggestions such as `cd cloud-hypervisor` useful from `$HOME` while
# preserving relative paths, CDPATH, named directories, flags, and every other
# native `cd` form.

_terminal_kit_project_roots() {
  emulate -L zsh
  local -a roots

  if [[ -n "${TERMINAL_KIT_PROJECT_DIRS:-}" ]]; then
    roots=("${(@s/:/)TERMINAL_KIT_PROJECT_DIRS}")
  else
    roots=("$HOME/Projects" "$HOME/projects")
  fi

  print -rl -- "${roots[@]}"
}

_terminal_kit_resolve_named_project() {
  emulate -L zsh
  local name="$1"
  local root candidate resolved
  local -a roots matches
  local -A seen

  roots=("${(@f)$(_terminal_kit_project_roots)}")
  matches=()

  for root in "${roots[@]}"; do
    [[ -n "$root" && -d "$root" ]] || continue
    candidate="$root/$name"
    [[ -d "$candidate" ]] || continue

    # `pwd -P` deduplicates case aliases and symlinked project roots before we
    # decide whether the basename is unambiguous.
    resolved="$(builtin cd -- "$candidate" 2>/dev/null && pwd -P)" || continue
    [[ -n "$resolved" ]] || continue
    [[ -n "${seen[$resolved]-}" ]] && continue
    seen[$resolved]=1
    matches+=("$resolved")

    # Never pick arbitrarily when two configured roots contain the same name.
    (( ${#matches} <= 1 )) || return 1
  done

  (( ${#matches} == 1 )) || return 1
  print -r -- "$matches[1]"
}

cd() {
  emulate -L zsh

  # Let the builtin own normal behavior first. Only a failed single bare name
  # gets the Terminal-Kit project lookup. Paths, options, `cd -`, and multi-arg
  # forms bypass this fallback entirely.
  if (( $# == 1 )) \
      && [[ -n "$1" ]] \
      && [[ "$1" != [+-]* ]] \
      && [[ "$1" != */* ]] \
      && [[ "$1" != "." && "$1" != ".." ]]; then
    if builtin cd "$1" 2>/dev/null; then
      return 0
    fi

    local resolved
    if resolved="$(_terminal_kit_resolve_named_project "$1")"; then
      builtin cd -- "$resolved"
      return $?
    fi

    # Re-run the original builtin unsilenced so Zsh reports its normal error.
    builtin cd "$1"
    return $?
  fi

  builtin cd "$@"
}
