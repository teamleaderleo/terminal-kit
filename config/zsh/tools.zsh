# terminal-kit: small wrappers for modern terminal tools.

# Yazi's shell wrapper returns the directory selected when the TUI exits.
if command -v yazi >/dev/null 2>&1; then
  y() {
    local _terminal_kit_yazi_tmp _terminal_kit_yazi_cwd
    _terminal_kit_yazi_tmp="$(mktemp -t 'yazi-cwd.XXXXXX')" || return
    command yazi "$@" --cwd-file="$_terminal_kit_yazi_tmp"
    IFS= read -r -d '' _terminal_kit_yazi_cwd < "$_terminal_kit_yazi_tmp"
    if [[ -n "$_terminal_kit_yazi_cwd" && "$_terminal_kit_yazi_cwd" != "$PWD" && -d "$_terminal_kit_yazi_cwd" ]]; then
      builtin cd -- "$_terminal_kit_yazi_cwd"
    fi
    command rm -f -- "$_terminal_kit_yazi_tmp"
    unset _terminal_kit_yazi_tmp _terminal_kit_yazi_cwd
  }
fi

if command -v lazygit >/dev/null 2>&1; then
  alias lg='lazygit'
fi

if command -v btop >/dev/null 2>&1; then
  alias bt='btop'
fi

if command -v fd >/dev/null 2>&1; then
  alias findf='fd --hidden --exclude .git'
fi

# Ordinary terminal output should keep wrapping. `wide` is the deliberate escape
# hatch for long table rows, logs, source lines, and diffs. less -S keeps each
# input line on one row; Left/Right move the viewport sideways.
wide() {
  if (( $# > 0 )); then
    command less -R -S -- "$@"
  else
    command less -R -S
  fi
}

# Copy common project values, literal text, a file, or piped input to the macOS
# clipboard. Git remotes are normalized to a clean browser URL when possible.
clip() {
  local mode="${1:-}" value label remote

  if [[ -z "$mode" ]]; then
    if [[ -t 0 ]]; then
      print -u2 -- 'Usage: clip path|branch|commit|remote|FILE|TEXT'
      print -u2 -- '       command | clip'
      return 2
    fi
    command pbcopy
    print -r -- 'copied stdin'
    return 0
  fi

  case "$mode" in
    path|pwd)
      value="$(builtin pwd -P)"
      label=path
      ;;
    branch)
      value="$(command git rev-parse --abbrev-ref HEAD 2>/dev/null)" || {
        print -u2 -- 'clip: outside a Git repository'
        return 1
      }
      label=branch
      ;;
    commit|sha)
      value="$(command git rev-parse HEAD 2>/dev/null)" || {
        print -u2 -- 'clip: outside a Git repository'
        return 1
      }
      label=commit
      ;;
    remote|repo)
      remote="$(command git remote get-url origin 2>/dev/null)" || {
        print -u2 -- 'clip: this repository has no origin remote'
        return 1
      }
      case "$remote" in
        git@*:*)
          value="https://${remote#git@}"
          value="${value/:/\/}"
          ;;
        ssh://git@*)
          value="https://${remote#ssh://git@}"
          ;;
        *)
          value="$remote"
          ;;
      esac
      value="${value%.git}"
      label=remote
      ;;
    *)
      if (( $# == 1 )) && [[ -f "$1" ]]; then
        command pbcopy < "$1"
        print -r -- "copied file: $1"
        return 0
      fi
      value="$*"
      label=text
      ;;
  esac

  print -rn -- "$value" | command pbcopy
  print -r -- "copied $label: $value"
}

# Compact, on-demand view of listening TCP ports. Pass a port number to filter.
ports() {
  local wanted="${1:-}" rows
  rows="$(command lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk -v wanted="$wanted" '
    NR == 1 { next }
    {
      endpoint = $9
      port = endpoint
      sub(/^.*:/, "", port)
      if (wanted != "" && port != wanted) next
      printf "%-18s %-8s %-7s %s\n", $1, $2, port, endpoint
    }
  ')"

  if [[ -z "$rows" ]]; then
    if [[ -n "$wanted" ]]; then
      print -r -- "no listener on TCP port $wanted"
    else
      print -r -- 'no listening TCP ports'
    fi
    return 0
  fi

  printf '%-18s %-8s %-7s %s\n' PROCESS PID PORT ADDRESS
  print -r -- "$rows"
}

# Run a command and send a cmux notification when it exits. The original status
# is preserved so `after npm test` still behaves correctly in scripts and shells.
after() {
  (( $# > 0 )) || {
    print -u2 -- 'Usage: after command [arguments...]'
    return 2
  }

  local command_text="${(j: :)${(q)@}}"
  local started=$SECONDS status elapsed title body

  "$@"
  status=$?
  elapsed=$(( SECONDS - started ))

  if (( status == 0 )); then
    title='Command finished'
  else
    title="Command failed ($status)"
  fi
  body="$command_text · ${elapsed}s"

  if command -v cmux >/dev/null 2>&1 \
    && command cmux notify --title "$title" --body "$body" >/dev/null 2>&1; then
    :
  elif command -v osascript >/dev/null 2>&1; then
    command osascript - "$title" "$body" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
  fi

  print -r -- "$title: $body"
  return $status
}

# A tiny daily scratch file. cmux opens it in-app; other terminals fall back to
# $EDITOR or TextEdit. Pass a path to open a different note.
scratch() {
  (( $# <= 1 )) || {
    print -u2 -- 'Usage: scratch [file]'
    return 2
  }

  local scratch_root="$HOME/.local/share/terminal-kit/scratch"
  local file
  if (( $# == 1 )); then
    file="$1"
    [[ "$file" == /* ]] || file="$PWD/$file"
  else
    file="$scratch_root/$(date +%Y-%m-%d).txt"
  fi

  command mkdir -p -- "${file:h}"
  if [[ ! -e "$file" ]]; then
    printf '%s\n\n' "$(date '+%A, %B %e, %Y')" > "$file"
  fi

  if command -v cmux >/dev/null 2>&1; then
    command cmux "$file"
  elif [[ -n "${EDITOR:-}" ]]; then
    local -a editor_command
    editor_command=(${(z)EDITOR})
    command "${editor_command[@]}" "$file"
  else
    command open -e "$file"
  fi

  print -r -- "$file"
}
