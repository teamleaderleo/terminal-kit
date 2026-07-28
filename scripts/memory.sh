#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$HOME/.config/terminal-kit"
STATE_FILE="$STATE_DIR/memory-mode"
CMUX_CONFIG="$HOME/.config/cmux/cmux.json"

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

apply_mode() {
  local mode="$1"
  local temporary

  require_jq
  [[ -r "$CMUX_CONFIG" ]] || fail "cmux config missing; run 'tk install'"

  temporary="$(mktemp -t terminal-kit-memory)"
  trap 'rm -f "$temporary"' EXIT
  render_mode "$mode" "$CMUX_CONFIG" "$temporary"
  jq empty "$temporary" >/dev/null

  mkdir -p "$STATE_DIR"
  mv "$temporary" "$CMUX_CONFIG"
  printf '%s\n' "$mode" > "$STATE_FILE"
  trap - EXIT

  reload_cmux
  printf 'terminal-kit: memory mode %s\n' "$mode"
  show_status
}

show_status() {
  local mode
  mode="$(current_mode)"
  printf 'terminal-kit memory\n'
  printf '  mode:                 %s\n' "$mode"

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

show_menu() {
  local selected
  if command -v fzf >/dev/null 2>&1; then
    selected="$(printf '%s\n' \
      $'balanced\tBalanced — six warm renderers; agents stay live' \
      $'lean\tLean — two warm renderers; hibernate agents above four' \
      $'ultra\tUltra — one warm renderer; hibernate agents above two' \
      $'normal\tNormal — restore cmux defaults' \
      $'status\tStatus — show the current memory policy' \
      $'top\tTask Manager — inspect actual CPU and RAM use' \
      | fzf --height=100% --layout=reverse --border --delimiter=$'\t' --with-nth=2.. --prompt='Memory > ' \
      | cut -f1)"
  else
    printf '1  balanced\n2  lean\n3  ultra\n4  normal\n5  status\n6  task manager\n'
    printf 'Choose: '
    read -r selected
    case "$selected" in
      1) selected=balanced ;;
      2) selected=lean ;;
      3) selected=ultra ;;
      4) selected=normal ;;
      5) selected=status ;;
      6) selected=top ;;
    esac
  fi

  case "${selected:-}" in
    normal|balanced|lean|ultra) apply_mode "$selected" ;;
    status) show_status ;;
    top) show_top ;;
    '') return 0 ;;
    *) fail "unknown menu selection: $selected" ;;
  esac
}

usage() {
  cat <<'HELP'
Usage: terminal-kit memory <command>

  status|current  Show the active policy and limits
  normal          cmux defaults: 12 warm renderers; agents remain live
  balanced        6 warm renderers; agents remain live (terminal-kit default)
  lean            2 warm renderers; hibernate supported agents above 4
  ultra           1 warm renderer; hibernate supported agents above 2
  menu            Open the interactive memory control
  top             Open cmux Task Manager

Renderer reclamation is non-destructive: shell processes and terminal state stay
alive. Agent hibernation only stops supported, restorable coding agents after they
are idle and off-screen; arbitrary shells and programs are never killed.
HELP
}

command_name="${1:-status}"
shift || true

case "$command_name" in
  status|current) show_status ;;
  normal|balanced|lean|ultra) apply_mode "$command_name" ;;
  menu|choose) show_menu ;;
  top|task-manager|resources) show_top ;;
  help|-h|--help) usage ;;
  *) fail "unknown memory command: $command_name" ;;
esac
