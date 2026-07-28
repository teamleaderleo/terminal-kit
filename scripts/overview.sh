#!/usr/bin/env bash
set -euo pipefail

CMUX_BIN="${TERMINAL_KIT_CMUX_BIN:-cmux}"
FZF_BIN="${TERMINAL_KIT_FZF_BIN:-fzf}"
JQ_BIN="${TERMINAL_KIT_JQ_BIN:-jq}"
OVERVIEW_TMP=""

cleanup() {
  [[ -z "$OVERVIEW_TMP" ]] || rm -f "$OVERVIEW_TMP"
}
trap cleanup EXIT

fail() {
  printf 'terminal-kit: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || fail "required command missing: $command_name"
}

cmux_ready() {
  "$CMUX_BIN" ping >/dev/null 2>&1
}

workspace_payload() {
  local window_ref="$1"
  "$CMUX_BIN" --window "$window_ref" list-workspaces --json
}

collect_rows() {
  local windows_json window_ref window_number window_key workspaces_json

  windows_json="$("$CMUX_BIN" list-windows --json)" || fail "could not read cmux windows"

  while IFS=$'\t' read -r window_ref window_number window_key; do
    [[ -n "$window_ref" ]] || continue
    workspaces_json="$(workspace_payload "$window_ref")" || fail "could not read workspaces for $window_ref"
    printf '%s\n' "$workspaces_json" | "$JQ_BIN" -r \
      --arg home "$HOME" \
      --arg window_ref "$window_ref" \
      --arg window_number "$window_number" \
      --argjson window_key "$window_key" '
        def payload: .result // .data // .;
        def clean: tostring | gsub("[[:cntrl:]]+"; " ");
        def shortdir($home):
          if . == null or . == "" then "—"
          elif . == $home then "~"
          elif startswith($home + "/") then "~/" + .[($home | length) + 1:]
          else .
          end;
        def clip($width):
          tostring as $value
          | if ($value | length) > $width then $value[:($width - 1)] + "…" else $value end;
        def pad($width):
          tostring as $value
          | if ($value | length) < $width then $value + (" " * ($width - ($value | length))) else $value end;
        def bold: "\u001b[1m";
        def dim: "\u001b[2m";
        def reset: "\u001b[0m";
        (payload.workspaces // [])[]
        | select((.ref // .id // "") != "")
        | (.index // 0) as $index
        | (.selected // false) as $selected
        | (.title // .custom_title // ("Workspace " + (($index + 1) | tostring)) | clean) as $title
        | (.current_directory | shortdir($home) | clean) as $directory
        | (if ($window_key and $selected) then "●" elif $selected then "○" else "·" end) as $marker
        | ("W" + $window_number + " · " + (($index + 1) | tostring) | pad(10)) as $location
        | ($title | clip(38) | pad(40)) as $display_title
        | ($marker + "  " + $location + $display_title + $directory) as $plain
        | (
            (if ($window_key and $selected) then bold + $marker + reset elif $selected then $marker else dim + $marker + reset end)
            + "  " + dim + $location + reset
            + (if ($window_key and $selected) then bold + $display_title + reset else $display_title end)
            + dim + $directory + reset
          ) as $styled
        | [
            $window_ref,
            (.ref // .id),
            $window_number,
            (($index + 1) | tostring),
            $plain,
            $styled
          ]
        | @tsv
      '
  done < <(
    printf '%s\n' "$windows_json" | "$JQ_BIN" -r '
      def payload: .result // .data // .;
      (payload.windows // [])[]
      | select((.ref // .id // "") != "")
      | [(.ref // .id), (((.index // 0) + 1) | tostring), ((.key // false) | tostring)]
      | @tsv
    '
  )
}

preview_workspace() {
  local window_ref="${1:-}"
  local workspace_ref="${2:-}"
  local window_number="${3:-?}"
  local workspace_number="${4:-?}"
  local workspaces_json

  [[ -n "$window_ref" && -n "$workspace_ref" ]] || return 0
  workspaces_json="$(workspace_payload "$window_ref" 2>/dev/null || true)"

  if [[ -n "$workspaces_json" ]]; then
    printf '%s\n' "$workspaces_json" | "$JQ_BIN" -r \
      --arg home "$HOME" \
      --arg workspace_ref "$workspace_ref" \
      --arg window_number "$window_number" \
      --arg workspace_number "$workspace_number" '
        def payload: .result // .data // .;
        def clean: tostring | gsub("[[:cntrl:]]+"; " ");
        def shortdir($home):
          if . == null or . == "" then ""
          elif . == $home then "~"
          elif startswith($home + "/") then "~/" + .[($home | length) + 1:]
          else .
          end;
        def clip($width):
          tostring as $value
          | if ($value | length) > $width then $value[:($width - 1)] + "…" else $value end;
        def bold: "\u001b[1m";
        def dim: "\u001b[2m";
        def reset: "\u001b[0m";
        (payload.workspaces // [])[]
        | select((.ref // .id) == $workspace_ref)
        | (.title // .custom_title // "Untitled workspace" | clean) as $title
        | (.current_directory | shortdir($home) | clean) as $directory
        | (.description // "" | clean) as $description
        | ((.listening_ports // []) | map(tostring) | join(", ")) as $ports
        | (.latest_submitted_message // .latest_conversation_message // "" | clean | clip(240)) as $activity
        | (
            bold + $title + reset
            + "\n" + dim + "Window " + $window_number + " · Workspace " + $workspace_number + reset
            + (if $directory != "" then "\n\n" + dim + "Directory" + reset + "\n" + $directory else "" end)
            + (if $description != "" then "\n\n" + dim + "Description" + reset + "\n" + $description else "" end)
            + (if $ports != "" then "\n\n" + dim + "Listening ports" + reset + "\n" + $ports else "" end)
            + (if $activity != "" then "\n\n" + dim + "Recent activity" + reset + "\n" + $activity else "" end)
          )
      '
  fi

  printf '\n\n\033[2mPane layout\033[0m\n'
  "$CMUX_BIN" --window "$window_ref" tree --workspace "$workspace_ref" 2>/dev/null \
    | sed 's/^/  /' || true
}

print_overview() {
  OVERVIEW_TMP="$(mktemp)"
  collect_rows > "$OVERVIEW_TMP"
  [[ -s "$OVERVIEW_TMP" ]] || fail "cmux has no workspaces to show"
  cut -f5 "$OVERVIEW_TMP"
}

open_overview() {
  local choice window_ref workspace_ref preview_command
  OVERVIEW_TMP="$(mktemp)"
  collect_rows > "$OVERVIEW_TMP"
  [[ -s "$OVERVIEW_TMP" ]] || fail "cmux has no workspaces to show"

  preview_command="$(printf '%q' "$0") __preview {1} {2} {3} {4}"
  if ! choice="$("$FZF_BIN" \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=6 \
    --nth=5 \
    --height=100% \
    --layout=reverse \
    --border=rounded \
    --margin=1,2 \
    --padding=1,2 \
    --cycle \
    --no-multi \
    --no-hscroll \
    --info=inline-right \
    --prompt='Overview › ' \
    --pointer='›' \
    --header='Every cmux window · type to filter · Enter focus · Esc return' \
    --preview="$preview_command" \
    --preview-window='right,54%,border-left,wrap' \
    < "$OVERVIEW_TMP")"; then
    exit 0
  fi

  IFS=$'\t' read -r window_ref workspace_ref _ <<< "$choice"
  [[ -n "$window_ref" && -n "$workspace_ref" ]] || fail "overview returned an invalid workspace"

  "$CMUX_BIN" --window "$window_ref" select-workspace --workspace "$workspace_ref" >/dev/null \
    || fail "could not select $workspace_ref"
  "$CMUX_BIN" focus-window --window "$window_ref" >/dev/null 2>&1 || true
}

usage() {
  cat <<'HELP'
Usage: terminal-kit overview [command]

  open          Open the full-screen cmux window and workspace overview
  list          Print the same overview as stable text

The overview inherits the active terminal palette, uses quiet typographic emphasis,
shows every cmux window and workspace, previews the selected pane tree, and returns
immediately with Esc.
HELP
}

command_name="${1:-open}"
shift || true

case "$command_name" in
  open|show|toggle)
    require_command "$CMUX_BIN"
    require_command "$JQ_BIN"
    require_command "$FZF_BIN"
    cmux_ready || fail "cmux is not running"
    open_overview
    ;;
  list)
    require_command "$CMUX_BIN"
    require_command "$JQ_BIN"
    cmux_ready || fail "cmux is not running"
    print_overview
    ;;
  __preview)
    require_command "$CMUX_BIN"
    require_command "$JQ_BIN"
    preview_workspace "${1:-}" "${2:-}" "${3:-?}" "${4:-?}"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    fail "unknown overview command: $command_name"
    ;;
esac
