#!/usr/bin/env bash

log() {
  printf 'terminal-kit: %s\n' "$*"
}

warn() {
  printf 'terminal-kit: warning: %s\n' "$*" >&2
}

die() {
  printf 'terminal-kit: error: %s\n' "$*" >&2
  exit 1
}

backup_file() {
  local file="$1"
  [[ -e "$file" ]] || return 0
  local safe_name="${file#/}"
  safe_name="${safe_name//\//__}"
  if [[ ! -e "$BACKUP_DIR/$safe_name" ]]; then
    cp -p "$file" "$BACKUP_DIR/$safe_name"
  fi
}

prune_ephemeral_zsh_sources() {
  local file="$1"
  [[ -e "$file" ]] || return 0

  local output
  output="$(mktemp)"
  awk '
    /^[[:space:]]*(source|\.)[[:space:]]+["\047]?\/tmp\/[^[:space:]"\047]+\/env["\047]?[[:space:]]*(#.*)?$/ { next }
    { print }
  ' "$file" > "$output"

  if ! cmp -s "$output" "$file"; then
    backup_file "$file"
    mv "$output" "$file"
    log "removed stale /tmp environment source from ~/.zshrc"
  else
    rm -f "$output"
  fi
}

# Print FILE without the begin..end block. A begin marker with no matching end
# marker (a hand-edited or truncated file) drops only the marker line, never the
# lines after it.
strip_managed_block() {
  local file="$1" begin="$2" end="$3"
  awk -v begin="$begin" -v end="$end" '
    { lines[NR] = $0 }
    END {
      i = 1
      while (i <= NR) {
        if (lines[i] == begin) {
          j = i + 1
          while (j <= NR && lines[j] != end) j++
          if (j <= NR) { i = j + 1; continue }
          i++
          continue
        }
        if (lines[i] != end) print lines[i]
        i++
      }
    }
  ' "$file"
}

replace_managed_block() {
  local file="$1"
  local name="$2"
  local begin="# >>> terminal-kit: $name >>>"
  local end="# <<< terminal-kit: $name <<<"
  local parent
  parent="$(dirname "$file")"

  local existed=false
  if [[ -e "$file" ]]; then
    existed=true
  fi
  mkdir -p "$parent"
  touch "$file"

  local body filtered trimmed output
  body="$(mktemp)"
  filtered="$(mktemp)"
  trimmed="$(mktemp)"
  output="$(mktemp)"
  cat > "$body"

  strip_managed_block "$file" "$begin" "$end" > "$filtered"

  awk '
    NF { last = NR }
    { lines[NR] = $0 }
    END { for (i = 1; i <= last; i++) print lines[i] }
  ' "$filtered" > "$trimmed"

  cat "$trimmed" > "$output"
  if [[ -s "$trimmed" ]]; then
    printf '\n' >> "$output"
  fi
  printf '%s\n' "$begin" >> "$output"
  cat "$body" >> "$output"
  printf '\n%s\n' "$end" >> "$output"
  if cmp -s "$output" "$file"; then
    rm -f "$output"
  else
    if [[ "$existed" == true ]]; then
      backup_file "$file"
    fi
    mv "$output" "$file"
  fi
  rm -f "$body" "$filtered" "$trimmed"
}

remove_managed_block() {
  local file="$1"
  local name="$2"
  [[ -e "$file" ]] || return 0

  local begin="# >>> terminal-kit: $name >>>"
  local end="# <<< terminal-kit: $name <<<"
  local raw output
  raw="$(mktemp)"
  output="$(mktemp)"

  strip_managed_block "$file" "$begin" "$end" > "$raw"

  awk '
    NF { last = NR }
    { lines[NR] = $0 }
    END { for (i = 1; i <= last; i++) print lines[i] }
  ' "$raw" > "$output"
  rm -f "$raw"

  if ! cmp -s "$output" "$file"; then
    backup_file "$file"
    mv "$output" "$file"
  else
    rm -f "$output"
  fi
}

reload_cmux() {
  # Tests and other non-interactive callers set TERMINAL_KIT_NO_RELOAD so a
  # fake-HOME run never touches the live cmux instance.
  [[ -z "${TERMINAL_KIT_NO_RELOAD:-}" ]] || return 0
  command -v cmux >/dev/null 2>&1 || return 0
  cmux ping >/dev/null 2>&1 || return 0
  cmux reload-config >/dev/null 2>&1 || cmux config reload >/dev/null 2>&1 || true
  log "reloaded cmux"
}

# Remove host state created by older terminal-kit versions.
remove_retired_state() {
  local label agent
  for label in com.terminal-kit.memory-auto com.teamleaderleo.terminal-kit-theme; do
    agent="$HOME/Library/LaunchAgents/$label.plist"
    [[ -e "$agent" ]] || continue
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    rm -f "$agent"
    log "removed retired LaunchAgent $label"
  done
  rm -f \
    "$HOME/.local/lib/terminal-kit/terminal-kit-memoryd" \
    "$HOME/.local/lib/terminal-kit/memoryd-source.sha256"
  rmdir "$HOME/.local/lib/terminal-kit" >/dev/null 2>&1 || true
  rm -f \
    "$HOME/.config/terminal-kit/hints" \
    "$HOME/.config/terminal-kit/hint-index" \
    "$HOME/.config/terminal-kit/hints-layout-v2"
}

# Keep only the newest backup directories.
prune_backups() {
  local root="$HOME/.config/terminal-kit-backups" keep="${1:-10}" dir
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d -print | sort -r | awk -v keep="$keep" 'NR > keep' \
    | while IFS= read -r dir; do
        rm -rf -- "$dir"
      done
}
