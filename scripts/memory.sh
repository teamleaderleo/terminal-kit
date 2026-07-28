#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/memory-mode"
AUTO_STATE_FILE="$STATE_DIR/memory-auto"
AUTO_RUNTIME_FILE="$STATE_DIR/memory-auto-runtime"
CMUX_CONFIG="$HOME/.config/cmux/cmux.json"
DAEMON_SOURCE="$ROOT/tools/memoryd/main.swift"
DAEMON_DIR="$HOME/.local/lib/terminal-kit"
DAEMON_BIN="$DAEMON_DIR/terminal-kit-memoryd"
DAEMON_HASH_FILE="$DAEMON_DIR/memoryd-source.sha256"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.terminal-kit.memory-auto.plist"
LAUNCH_LABEL="com.terminal-kit.memory-auto"
LOG_FILE="$HOME/Library/Logs/terminal-kit-memoryd.log"
TERMINAL_KIT_BIN="$HOME/.local/bin/terminal-kit"

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || fail "jq is missing; run 'tk tools'"
}

current_mode() {
  local mode="balanced"
  if [[ -r "$STATE_FILE" ]]; then
    mode="$(tr -d '[:space:]' < "$STATE_FILE")"
  fi
  case "$mode" in
    normal|balanced|lean|ultra) printf '%s\n' "$mode" ;;
    *) printf 'balanced\n' ;;
  esac
}

current_auto_state() {
  local state="off"
  if [[ -r "$AUTO_STATE_FILE" ]]; then
    state="$(tr -d '[:space:]' < "$AUTO_STATE_FILE")"
  fi
  case "$state" in
    on|off) printf '%s\n' "$state" ;;
    *) printf 'off\n' ;;
  esac
}

render_mode() {
  local mode="$1"
  local input="$2"
  local output="$3"
  local renderer_idle renderer_warm agents_enabled agent_idle agent_live

  case "$mode" in
    normal)
      renderer_idle=30
      renderer_warm=12
      agents_enabled=false
      agent_idle=5
      agent_live=12
      ;;
    balanced)
      renderer_idle=15
      renderer_warm=6
      agents_enabled=false
      agent_idle=5
      agent_live=8
      ;;
    lean)
      renderer_idle=5
      renderer_warm=2
      agents_enabled=true
      agent_idle=5
      agent_live=4
      ;;
    ultra)
      renderer_idle=5
      renderer_warm=1
      agents_enabled=true
      agent_idle=5
      agent_live=2
      ;;
    *)
      fail "unknown memory mode: $mode"
      ;;
  esac

  jq \
    --argjson renderer_idle "$renderer_idle" \
    --argjson renderer_warm "$renderer_warm" \
    --argjson agents_enabled "$agents_enabled" \
    --argjson agent_idle "$agent_idle" \
    --argjson agent_live "$agent_live" \
    '
      .terminal.rendererRealization = {
        enabled: true,
        idleSeconds: $renderer_idle,
        maxWarmRenderers: $renderer_warm
      }
      | .terminal.agentHibernation = {
          enabled: $agents_enabled,
          idleSeconds: $agent_idle,
          maxLiveTerminals: $agent_live
        }
    ' "$input" > "$output"
}

reload_cmux() {
  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
    cmux reload-config >/dev/null 2>&1 || cmux config reload >/dev/null 2>&1 || true
  fi
}

record_runtime() {
  local pressure="$1"
  local mode="$2"
  mkdir -p "$STATE_DIR"
  cat > "$AUTO_RUNTIME_FILE" <<EOF_RUNTIME
pressure=$pressure
effective_mode=$mode
updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF_RUNTIME
}

runtime_value() {
  local key="$1"
  [[ -r "$AUTO_RUNTIME_FILE" ]] || return 0
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$AUTO_RUNTIME_FILE"
}

launch_domain() {
  printf 'gui/%s\n' "$(id -u)"
}

stop_auto_daemon() {
  local quiet="${1:-false}"
  local domain
  domain="$(launch_domain)"
  launchctl bootout "$domain/$LAUNCH_LABEL" >/dev/null 2>&1 || true
  if [[ "$quiet" != true ]]; then
    printf 'terminal-kit: automatic memory policy stopped\n'
  fi
}

swiftc_path() {
  if command -v xcrun >/dev/null 2>&1; then
    xcrun --find swiftc 2>/dev/null && return 0
  fi
  command -v swiftc 2>/dev/null || true
}

compile_daemon() {
  local compiler source_hash saved_hash temporary
  [[ "$(uname -s)" == "Darwin" ]] || fail "automatic memory mode requires macOS"
  [[ -r "$DAEMON_SOURCE" ]] || fail "memory daemon source missing: $DAEMON_SOURCE"

  compiler="$(swiftc_path)"
  [[ -n "$compiler" ]] || fail "Swift compiler missing; install Apple's Command Line Tools"

  source_hash="$(shasum -a 256 "$DAEMON_SOURCE" | awk '{print $1}')"
  saved_hash=""
  [[ -r "$DAEMON_HASH_FILE" ]] && saved_hash="$(tr -d '[:space:]' < "$DAEMON_HASH_FILE")"
  if [[ -x "$DAEMON_BIN" && "$source_hash" == "$saved_hash" ]]; then
    return 0
  fi

  mkdir -p "$DAEMON_DIR"
  temporary="$(mktemp -t terminal-kit-memoryd)"
  trap 'rm -f "$temporary"' RETURN
  "$compiler" -O -parse-as-library "$DAEMON_SOURCE" -o "$temporary"
  chmod 755 "$temporary"
  mv "$temporary" "$DAEMON_BIN"
  printf '%s\n' "$source_hash" > "$DAEMON_HASH_FILE"
  trap - RETURN
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

write_launch_agent() {
  local terminal_kit daemon auto_state log_path
  terminal_kit="$TERMINAL_KIT_BIN"
  [[ -x "$terminal_kit" ]] || terminal_kit="$ROOT/bin/terminal-kit"
  daemon="$(xml_escape "$DAEMON_BIN")"
  terminal_kit="$(xml_escape "$terminal_kit")"
  auto_state="$(xml_escape "$AUTO_STATE_FILE")"
  log_path="$(xml_escape "$LOG_FILE")"

  mkdir -p "$(dirname "$LAUNCH_AGENT")" "$(dirname "$LOG_FILE")"
  cat > "$LAUNCH_AGENT" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LAUNCH_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$daemon</string>
    <string>--terminal-kit</string>
    <string>$terminal_kit</string>
    <string>--auto-state</string>
    <string>$auto_state</string>
    <string>--log</string>
    <string>$log_path</string>
    <string>--recovery-seconds</string>
    <string>300</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>LowPriorityIO</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$log_path</string>
  <key>StandardErrorPath</key>
  <string>$log_path</string>
</dict>
</plist>
EOF_PLIST
  plutil -lint "$LAUNCH_AGENT" >/dev/null
}

start_auto_daemon() {
  local domain
  compile_daemon
  write_launch_agent
  domain="$(launch_domain)"
  launchctl bootout "$domain/$LAUNCH_LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "$domain" "$LAUNCH_AGENT"
  launchctl kickstart -k "$domain/$LAUNCH_LABEL" >/dev/null 2>&1 || true
}

apply_mode() {
  local mode="$1"
  local origin="${2:-manual}"
  local pressure="${3:-manual}"
  local temporary

  require_jq
  [[ -r "$CMUX_CONFIG" ]] || fail "cmux config missing; run 'tk install'"

  if [[ "$origin" == manual && "$(current_auto_state)" == on ]]; then
    printf 'off\n' > "$AUTO_STATE_FILE"
    stop_auto_daemon true
    printf 'terminal-kit: automatic memory policy disabled by manual selection\n'
  fi

  temporary="$(mktemp -t terminal-kit-memory)"
  trap 'rm -f "$temporary"' RETURN
  render_mode "$mode" "$CMUX_CONFIG" "$temporary"
  jq empty "$temporary" >/dev/null

  mkdir -p "$STATE_DIR"
  if ! cmp -s "$temporary" "$CMUX_CONFIG"; then
    mv "$temporary" "$CMUX_CONFIG"
    reload_cmux
  else
    rm -f "$temporary"
  fi
  printf '%s\n' "$mode" > "$STATE_FILE"
  trap - RETURN

  if [[ "$origin" == auto ]]; then
    record_runtime "$pressure" "$mode"
  else
    printf 'terminal-kit: memory mode %s\n' "$mode"
    show_status
  fi
}

auto_on() {
  mkdir -p "$STATE_DIR"
  printf 'on\n' > "$AUTO_STATE_FILE"
  if ! start_auto_daemon; then
    printf 'off\n' > "$AUTO_STATE_FILE"
    fail "could not start automatic memory policy"
  fi
  printf 'terminal-kit: automatic memory policy on\n'
  printf 'terminal-kit: warning → lean, critical → ultra, normal for 5 minutes → balanced\n'
  show_status
}

auto_off() {
  mkdir -p "$STATE_DIR"
  printf 'off\n' > "$AUTO_STATE_FILE"
  stop_auto_daemon true
  printf 'terminal-kit: automatic memory policy off; current mode stays %s\n' "$(current_mode)"
}

auto_refresh() {
  [[ "$(current_auto_state)" == on ]] || return 0
  start_auto_daemon
}

auto_apply() {
  local mode="${1:-}"
  local pressure="${2:-unknown}"
  [[ "$(current_auto_state)" == on ]] || exit 0
  case "$mode" in
    balanced|lean|ultra) ;;
    *) fail "invalid automatic memory mode: $mode" ;;
  esac

  if [[ "$(current_mode)" == "$mode" ]]; then
    record_runtime "$pressure" "$mode"
    exit 0
  fi
  apply_mode "$mode" auto "$pressure"
}

show_status() {
  local mode auto_state pressure updated daemon_state
  mode="$(current_mode)"
  auto_state="$(current_auto_state)"
  pressure="$(runtime_value pressure)"
  updated="$(runtime_value updated_at)"
  daemon_state="stopped"
  if launchctl print "$(launch_domain)/$LAUNCH_LABEL" >/dev/null 2>&1; then
    daemon_state="running"
  fi

  printf 'terminal-kit memory\n'
  printf '  mode:                 %s\n' "$mode"
  printf '  automatic:            %s (%s)\n' "$auto_state" "$daemon_state"
  [[ -n "$pressure" ]] && printf '  last pressure:        %s\n' "$pressure"
  [[ -n "$updated" ]] && printf '  last transition:      %s\n' "$updated"

  if [[ -r "$CMUX_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    printf '  warm renderers:       %s\n' "$(jq -r '.terminal.rendererRealization.maxWarmRenderers // 12' "$CMUX_CONFIG")"
    printf '  renderer idle delay:  %ss\n' "$(jq -r '.terminal.rendererRealization.idleSeconds // 30' "$CMUX_CONFIG")"
    printf '  agent hibernation:    %s\n' "$(jq -r 'if .terminal.agentHibernation.enabled == true then "on" else "off" end' "$CMUX_CONFIG")"
    printf '  live agent cap:       %s\n' "$(jq -r '.terminal.agentHibernation.maxLiveTerminals // 12' "$CMUX_CONFIG")"
  fi
}

show_top() {
  command -v cmux >/dev/null 2>&1 || fail "cmux CLI not found"
  cmux ping >/dev/null 2>&1 || fail "cmux is not running"
  exec cmux top
}

show_log() {
  if [[ -r "$LOG_FILE" ]]; then
    tail -n "${1:-40}" "$LOG_FILE"
  else
    printf 'terminal-kit: no automatic memory log yet\n'
  fi
}

show_menu() {
  local selected
  if command -v fzf >/dev/null 2>&1; then
    selected="$(printf '%s\n' \
      $'auto-on\tAutomatic — follow macOS memory pressure' \
      $'auto-off\tAutomatic off — freeze the current policy' \
      $'balanced\tBalanced — six warm renderers; agents stay live' \
      $'lean\tLean — two warm renderers; hibernate agents above four' \
      $'ultra\tUltra — one warm renderer; hibernate agents above two' \
      $'normal\tNormal — restore cmux defaults' \
      $'status\tStatus — show the current memory policy' \
      $'top\tTask Manager — inspect actual CPU and RAM use' \
      | fzf --height=100% --layout=reverse --border --delimiter=$'\t' --with-nth=2.. --prompt='Memory > ' \
      | cut -f1)"
  else
    printf '1  automatic on\n2  automatic off\n3  balanced\n4  lean\n5  ultra\n6  normal\n7  status\n8  task manager\n'
    printf 'Choose: '
    read -r selected
    case "$selected" in
      1) selected=auto-on ;;
      2) selected=auto-off ;;
      3) selected=balanced ;;
      4) selected=lean ;;
      5) selected=ultra ;;
      6) selected=normal ;;
      7) selected=status ;;
      8) selected=top ;;
    esac
  fi

  case "${selected:-}" in
    auto-on) auto_on ;;
    auto-off) auto_off ;;
    normal|balanced|lean|ultra) apply_mode "$selected" ;;
    status) show_status ;;
    top) show_top ;;
    '') return 0 ;;
    *) fail "unknown menu selection: $selected" ;;
  esac
}

auto_command() {
  case "${1:-status}" in
    on|enable|start) auto_on ;;
    off|disable|stop) auto_off ;;
    status|current) show_status ;;
    refresh|restart) auto_refresh ;;
    log|logs) show_log "${2:-40}" ;;
    *) fail "Usage: terminal-kit memory auto on|off|status|log" ;;
  esac
}

usage() {
  cat <<'HELP'
Usage: terminal-kit memory <command>

  status|current  Show the active policy and limits
  auto on         Follow native macOS normal/warning/critical pressure events
  auto off        Stop automatic changes and keep the current effective mode
  auto log        Show recent automatic transitions
  normal          cmux defaults: 12 warm renderers; agents remain live
  balanced        6 warm renderers; agents remain live (terminal-kit default)
  lean            2 warm renderers; hibernate supported agents above 4
  ultra           1 warm renderer; hibernate supported agents above 2
  menu            Open the interactive memory control
  top             Open cmux Task Manager

Automatic mode is event-driven rather than polled. Warning pressure selects lean,
critical pressure selects ultra, and five stable minutes at normal pressure return
to balanced. Manual mode selection turns automatic mode off.

Renderer reclamation is non-destructive: shell processes and terminal state stay
alive. Agent hibernation only stops supported, restorable coding agents after they
are idle and off-screen; arbitrary shells and programs are never killed.
HELP
}

command_name="${1:-status}"
shift || true

case "$command_name" in
  status|current) show_status ;;
  auto) auto_command "$@" ;;
  normal|balanced|lean|ultra) apply_mode "$command_name" ;;
  menu|choose) show_menu ;;
  top|task-manager|resources) show_top ;;
  log|logs) show_log "${1:-40}" ;;
  _auto-apply) auto_apply "$@" ;;
  help|-h|--help) usage ;;
  *) fail "unknown memory command: $command_name" ;;
esac
