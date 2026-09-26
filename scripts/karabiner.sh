#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

LIVE_CONFIG="${TERMINAL_KIT_KARABINER_CONFIG:-$HOME/.config/karabiner/karabiner.json}"
ASSET_SOURCE="$ROOT/config/karabiner/terminal-kit.json"
ASSET_TARGET="${TERMINAL_KIT_KARABINER_ASSET:-$HOME/.config/karabiner/assets/complex_modifications/terminal-kit.json}"
MANAGED_DESCRIPTION="terminal-kit: browser-style cmux surface switching"
KARABINER_APP="/Applications/Karabiner-Elements.app"
KARABINER_CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
quiet=false
owned_backup_dir=false

usage() {
  cat <<'HELP'
Usage: terminal-kit karabiner <command>

  status          Show whether the terminal-kit rule is in the selected profile
  apply | sync    Add or refresh the terminal-kit rule in the selected profile

The rule maps Cmd-Shift-] / Cmd-Shift-[ to Ctrl-Tab / Ctrl-Shift-Tab inside cmux.
Everything else in your Karabiner config is left alone.
HELP
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required for Karabiner settings"
}

say() {
  [[ "$quiet" == true ]] || log "$*"
}

ensure_backup_dir() {
  if [[ -z "${BACKUP_DIR:-}" ]]; then
    BACKUP_DIR="$HOME/.config/terminal-kit-backups/$(date +%Y%m%d-%H%M%S)-karabiner"
    export BACKUP_DIR
    mkdir -p "$BACKUP_DIR"
    owned_backup_dir=true
  fi
}

cleanup_backup_dir() {
  if [[ "$owned_backup_dir" == true && -d "${BACKUP_DIR:-}" && -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
    rmdir "$BACKUP_DIR"
  fi
}
trap cleanup_backup_dir EXIT

karabiner_present() {
  [[ -e "$LIVE_CONFIG" || -d "$KARABINER_APP" || -x "$KARABINER_CLI" ]]
}

selected_profile_index() {
  jq -r '
    (.profiles // []) as $profiles
    | ([range(0; $profiles | length) as $i | select($profiles[$i].selected == true) | $i] | first)
      // (if ($profiles | length) > 0 then 0 else empty end)
  ' "$LIVE_CONFIG"
}

selected_profile_name() {
  local index="$1"
  jq -r --argjson index "$index" '.profiles[$index].name // "unnamed"' "$LIVE_CONFIG"
}

validate_live_config() {
  [[ -r "$LIVE_CONFIG" ]] || return 1
  jq empty "$LIVE_CONFIG" || die "Karabiner config is invalid JSON: $LIVE_CONFIG"
  local count
  count="$(jq -r '(.profiles // []) | length' "$LIVE_CONFIG")"
  (( count > 0 )) || die "Karabiner config has no profiles: $LIVE_CONFIG"
}

sync_asset() {
  [[ -r "$ASSET_SOURCE" ]] || die "managed Karabiner rule is missing: $ASSET_SOURCE"
  jq empty "$ASSET_SOURCE" || die "managed Karabiner rule is invalid JSON"

  mkdir -p "$(dirname "$ASSET_TARGET")"
  if [[ ! -e "$ASSET_TARGET" ]] || ! cmp -s "$ASSET_SOURCE" "$ASSET_TARGET"; then
    ensure_backup_dir
    [[ -e "$ASSET_TARGET" ]] && backup_file "$ASSET_TARGET"
    cp "$ASSET_SOURCE" "$ASSET_TARGET"
    say "synced Karabiner rule asset"
  fi
}

render_applied_config() {
  local index="$1" tmp="$2" rule
  rule="$(jq '.rules[0]' "$ASSET_SOURCE")"
  [[ "$rule" != null ]] || die "managed Karabiner rule file has no rule"

  jq \
    --argjson index "$index" \
    --argjson managed_rule "$rule" \
    --arg managed_description "$MANAGED_DESCRIPTION" '
      .profiles[$index].complex_modifications //= {} |
      .profiles[$index].complex_modifications.rules = (
        [(.profiles[$index].complex_modifications.rules // [])[]
          | select((.description // "") != $managed_description)]
        + [$managed_rule]
      )
    ' "$LIVE_CONFIG" > "$tmp"
}

apply_settings() {
  need_jq
  karabiner_present || return 0
  sync_asset

  if [[ ! -r "$LIVE_CONFIG" ]]; then
    [[ "$quiet" == true ]] || warn "Karabiner is installed but has no initialized config yet; open it once, then run tk"
    return 0
  fi

  validate_live_config
  local index profile tmp
  index="$(selected_profile_index)"
  [[ -n "$index" ]] || die "could not resolve a Karabiner profile"
  profile="$(selected_profile_name "$index")"
  tmp="$(mktemp -t terminal-kit-karabiner.XXXXXX)"
  render_applied_config "$index" "$tmp"
  jq empty "$tmp"

  if ! cmp -s "$tmp" "$LIVE_CONFIG"; then
    ensure_backup_dir
    backup_file "$LIVE_CONFIG"
    cp "$tmp" "$LIVE_CONFIG"
    say "synced Karabiner profile: $profile"
  fi
  rm -f "$tmp"
}

show_status() {
  need_jq
  printf 'terminal-kit Karabiner\n'
  printf 'live config: %s\n' "${LIVE_CONFIG/#$HOME/\~}"
  if [[ -r "$LIVE_CONFIG" ]] && jq empty "$LIVE_CONFIG" >/dev/null 2>&1; then
    local index profile managed
    index="$(selected_profile_index || true)"
    profile="-"
    managed=false
    if [[ -n "$index" ]]; then
      profile="$(selected_profile_name "$index")"
      managed="$(jq -r --argjson index "$index" --arg desc "$MANAGED_DESCRIPTION" '
        any((.profiles[$index].complex_modifications.rules // [])[]; (.description // "") == $desc)
      ' "$LIVE_CONFIG")"
    fi
    printf 'profile:     %s\n' "$profile"
    printf 'cmux alias:  %s\n' "$managed"
  else
    printf 'profile:     unavailable\n'
    printf 'cmux alias:  false\n'
  fi
}

command_name="${1:-status}"
shift || true
case "$command_name" in
  apply|sync)
    if [[ "${1:-}" == --quiet ]]; then quiet=true; shift; fi
    (( $# == 0 )) || die "unexpected Karabiner arguments: $*"
    apply_settings
    ;;
  status)
    (( $# == 0 )) || die "unexpected Karabiner arguments: $*"
    show_status
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    printf 'terminal-kit: unknown Karabiner command: %s\n' "$command_name" >&2
    usage >&2
    exit 2
    ;;
esac
