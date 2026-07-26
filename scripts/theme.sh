#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

TOP_THEMES=(
  "Catppuccin Mocha"
  "Violite"
  "Vesper"
  "Sea Shells"
  "Rose Pine"
  "Rose Pine Moon"
  "Mellow"
  "Lovelace"
  "Jellybeans"
  "Fairyfloss"
  "Catppuccin Macchiato"
)

SECONDARY_THEMES=(
  "Novel"
  "Subliminal"
  "Monokai Pro Spectrum"
  "Monokai Pro Octagon"
  "Monokai Pro"
  "Lavendula"
  "Niji"
  "Kanso Zen"
  "Cyberpunk"
  "Ciapre"
  "Chalkboard"
  "Carbonfox"
  "Builtin Pastel Dark"
  "Broadcast"
  "Ayu Mirage"
  "Ayu"
  "Atom One Dark"
  "Atom"
  "Aizen Dark"
)

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

require_cmux() {
  command -v cmux >/dev/null 2>&1 || fail "cmux CLI not found"
}

current_dark_theme() {
  require_cmux
  cmux themes list 2>/dev/null | sed -n 's/^Current dark: //p' | head -n 1
}

same_theme() {
  local left right
  left="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  right="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  [[ "$left" == "$right" ]]
}

set_theme() {
  local theme="$1"
  require_cmux
  cmux themes set "$theme"
  printf 'terminal-kit: theme set to %s\n' "$theme"
}

show_shortlist() {
  printf 'Top themes:\n'
  local theme
  for theme in "${TOP_THEMES[@]}"; do
    printf '  %s\n' "$theme"
  done
  printf '\nSecondary themes:\n'
  for theme in "${SECONDARY_THEMES[@]}"; do
    printf '  %s\n' "$theme"
  done
}

next_theme() {
  local current index next_index count
  current="$(current_dark_theme || true)"
  count=${#TOP_THEMES[@]}
  next_index=0

  for ((index = 0; index < count; index++)); do
    if same_theme "$current" "${TOP_THEMES[$index]}"; then
      next_index=$(((index + 1) % count))
      break
    fi
  done

  set_theme "${TOP_THEMES[$next_index]}"
}

random_theme() {
  local number index count
  count=${#TOP_THEMES[@]}
  number="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
  index=$((number % count))
  set_theme "${TOP_THEMES[$index]}"
}

daily_theme() {
  local year day index count target current
  year="$(date +%Y)"
  day="$(date +%j)"
  count=${#TOP_THEMES[@]}
  index=$(((10#$year * 366 + 10#$day) % count))
  target="${TOP_THEMES[$index]}"
  current="$(current_dark_theme || true)"

  if same_theme "$current" "$target"; then
    printf 'terminal-kit: daily theme remains %s\n' "$target"
    return
  fi

  set_theme "$target"
}

launch_agent_path() {
  printf '%s\n' "$HOME/Library/LaunchAgents/com.teamleaderleo.terminal-kit-theme.plist"
}

auto_on() {
  local plist log_dir
  plist="$(launch_agent_path)"
  log_dir="$HOME/Library/Logs"
  mkdir -p "$(dirname "$plist")" "$log_dir"

  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.teamleaderleo.terminal-kit-theme</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/scripts/theme.sh</string>
    <string>daily</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>21600</integer>
  <key>StandardOutPath</key>
  <string>$log_dir/terminal-kit-theme.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/terminal-kit-theme.log</string>
</dict>
</plist>
EOF

  launchctl bootout "gui/$UID/com.teamleaderleo.terminal-kit-theme" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID" "$plist"
  printf 'terminal-kit: daily theme rotation enabled\n'
}

auto_off() {
  local plist
  plist="$(launch_agent_path)"
  launchctl bootout "gui/$UID/com.teamleaderleo.terminal-kit-theme" >/dev/null 2>&1 || true
  rm -f "$plist"
  printf 'terminal-kit: daily theme rotation disabled\n'
}

auto_status() {
  local plist
  plist="$(launch_agent_path)"
  if [[ -f "$plist" ]]; then
    printf 'terminal-kit: daily theme rotation configured\n'
    launchctl print "gui/$UID/com.teamleaderleo.terminal-kit-theme" >/dev/null 2>&1 \
      && printf 'terminal-kit: launch agent is loaded\n' \
      || printf 'terminal-kit: launch agent is not loaded\n'
  else
    printf 'terminal-kit: daily theme rotation is off\n'
  fi
}

usage() {
  cat <<'HELP'
Usage: terminal-kit theme <command>

  browse              Open cmux's interactive theme browser
  current             Show the active light/dark themes
  shortlist           Show the saved ranked shortlist
  set <name>          Set one theme for light and dark appearance
  next                Move to the next top-ranked theme
  random              Pick a random top-ranked theme
  daily               Apply today's deterministic top-ranked theme
  auto on|off|status  Manage automatic daily rotation with launchd
  clear               Remove cmux's managed theme override
HELP
}

command_name="${1:-browse}"
shift || true

case "$command_name" in
  browse)
    require_cmux
    exec cmux themes
    ;;
  current)
    require_cmux
    exec cmux themes list
    ;;
  shortlist|list)
    show_shortlist
    ;;
  set)
    [[ $# -gt 0 ]] || fail "theme set requires a name"
    set_theme "$*"
    ;;
  next)
    next_theme
    ;;
  random)
    random_theme
    ;;
  daily)
    daily_theme
    ;;
  auto)
    case "${1:-status}" in
      on) auto_on ;;
      off) auto_off ;;
      status) auto_status ;;
      *) fail "theme auto expects on, off, or status" ;;
    esac
    ;;
  clear)
    require_cmux
    exec cmux themes clear
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown theme command: $command_name"
    ;;
esac
