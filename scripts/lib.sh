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

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skipping = 1; next }
    $0 == end   { skipping = 0; next }
    !skipping   { print }
  ' "$file" > "$filtered"

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

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skipping = 1; next }
    $0 == end   { skipping = 0; next }
    !skipping   { print }
  ' "$file" > "$raw"

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
