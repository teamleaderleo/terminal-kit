#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

POLICY_FILE="$ROOT/config/agent-policy.json"
STATE_ROOT="${TERMINAL_KIT_WORK_STATE_ROOT:-$HOME/.local/state/terminal-kit/work}"

usage() {
  cat <<'HELP'
Usage:
  terminal-kit agent context [--json]
  terminal-kit agent policy
  terminal-kit agent current [id|last]
  terminal-kit agent events [id|last]
  terminal-kit agent checkpoint <todo|working|needs-attention|review|done> [summary] [--proof text] [--next text] [--id id]

This interface is primarily for coding agents and automation. `context --json` is
the stable bootstrap: policy, repository state, task receipt, guidance files,
available agent CLIs, cmux context, and recent terminal-kit work in one object.
HELP
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required for the agent interface"
}

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

current_repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$root" ]] || return 1
  canonical_dir "$root"
}

receipt_for_id() {
  local requested="${1:-last}" id file
  if [[ "$requested" == last ]]; then
    [[ -r "$STATE_ROOT/last" ]] || return 1
    id="$(tr -d '[:space:]' < "$STATE_ROOT/last")"
  else
    id="$requested"
  fi
  file="$STATE_ROOT/$id.json"
  [[ -r "$file" ]] || return 1
  printf '%s\n' "$file"
}

current_receipt() {
  local repo file work_path canonical_work
  repo="$(current_repo_root 2>/dev/null || true)"
  [[ -n "$repo" && -d "$STATE_ROOT" ]] || return 1

  for file in "$STATE_ROOT"/*.json; do
    [[ -r "$file" ]] || continue
    work_path="$(jq -r '.work_path // empty' "$file" 2>/dev/null || true)"
    [[ -n "$work_path" && -d "$work_path" ]] || continue
    canonical_work="$(canonical_dir "$work_path" 2>/dev/null || true)"
    [[ "$canonical_work" == "$repo" ]] || continue
    printf '%s\n' "$file"
    return 0
  done
  return 1
}

resolve_receipt() {
  local requested="${1:-}"
  if [[ -n "$requested" ]]; then
    receipt_for_id "$requested" || die "unknown terminal-kit work receipt: $requested"
    return 0
  fi
  current_receipt || receipt_for_id last || die "no terminal-kit work receipt is available"
}

json_array_from_lines() {
  jq -R . | jq -s .
}

context_json() {
  need_jq
  [[ -r "$POLICY_FILE" ]] || die "agent policy missing at $POLICY_FILE"

  local cwd repo branch head remote dirty=false guidance_json agents_json work_json recent_json
  local cmux_available=false receipt name
  cwd="$(pwd -P)"
  repo="$(current_repo_root 2>/dev/null || true)"
  branch=""
  head=""
  remote=""

  if [[ -n "$repo" ]]; then
    branch="$(git -C "$repo" branch --show-current 2>/dev/null || true)"
    head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
    remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
    [[ -n "$(git -C "$repo" status --porcelain --untracked-files=all 2>/dev/null || true)" ]] && dirty=true
  fi

  guidance_json="$(
    {
      if [[ -n "$repo" ]]; then
        for name in AGENTS.md STENSIBLY.md CLAUDE.md CONTRIBUTING.md README.md docs/current-wave.md docs/ROADMAP.md; do
          if [[ -f "$repo/$name" ]]; then
            printf '%s\n' "$name"
          fi
        done
      fi
      true
    } | json_array_from_lines
  )"

  agents_json="$(
    {
      for name in codex claude opencode pi gemini; do
        if command -v "$name" >/dev/null 2>&1; then
          printf '%s\n' "$name"
        fi
      done
      true
    } | json_array_from_lines
  )"

  work_json=null
  if receipt="$(current_receipt 2>/dev/null)"; then
    work_json="$(cat "$receipt")"
  fi

  recent_json='[]'
  if [[ -d "$STATE_ROOT" ]] && compgen -G "$STATE_ROOT/*.json" >/dev/null 2>&1; then
    recent_json="$(jq -s 'sort_by(.created_at // "") | reverse | .[:5]' "$STATE_ROOT"/*.json)"
  fi

  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
    cmux_available=true
  fi

  jq -n \
    --arg protocol "terminal-kit-agent/v1" \
    --arg cwd "$cwd" \
    --arg repo_root "$repo" \
    --arg branch "$branch" \
    --arg head "$head" \
    --arg remote "$remote" \
    --arg cmux_workspace "${CMUX_WORKSPACE_ID:-}" \
    --arg cmux_surface "${CMUX_SURFACE_ID:-}" \
    --arg cmux_tab "${CMUX_TAB_ID:-}" \
    --argjson dirty "$dirty" \
    --argjson guidance "$guidance_json" \
    --argjson agents "$agents_json" \
    --argjson work "$work_json" \
    --argjson recent "$recent_json" \
    --argjson policy "$(cat "$POLICY_FILE")" \
    --argjson cmux_available "$cmux_available" \
    '{
      protocol: $protocol,
      cwd: $cwd,
      repository: {
        root: (if $repo_root == "" then null else $repo_root end),
        branch: (if $branch == "" then null else $branch end),
        head: (if $head == "" then null else $head end),
        origin: (if $remote == "" then null else $remote end),
        dirty: $dirty,
        guidance: $guidance
      },
      work: $work,
      recentWork: $recent,
      agents: $agents,
      cmux: {
        available: $cmux_available,
        workspaceId: (if $cmux_workspace == "" then null else $cmux_workspace end),
        surfaceId: (if $cmux_surface == "" then null else $cmux_surface end),
        tabId: (if $cmux_tab == "" then null else $cmux_tab end)
      },
      policy: $policy
    }'
}

context_human() {
  local json
  json="$(context_json)"
  printf 'terminal-kit agent context\n'
  printf 'repo:      %s\n' "$(printf '%s' "$json" | jq -r '.repository.root // "outside Git"')"
  printf 'branch:    %s\n' "$(printf '%s' "$json" | jq -r '.repository.branch // "-"')"
  printf 'work:      %s\n' "$(printf '%s' "$json" | jq -r '.work.id // "none"')"
  printf 'state:     %s\n' "$(printf '%s' "$json" | jq -r '.work.state // "-"')"
  printf 'agents:    %s\n' "$(printf '%s' "$json" | jq -r '.agents | join(", ")')"
  printf 'guidance:  %s\n' "$(printf '%s' "$json" | jq -r '.repository.guidance | join(", ")')"
  printf 'cmux:      %s\n' "$(printf '%s' "$json" | jq -r 'if .cmux.available then "available" else "unavailable" end')"
}

show_policy() {
  need_jq
  jq . "$POLICY_FILE"
}

show_current() {
  need_jq
  local file
  file="$(resolve_receipt "${1:-}")"
  jq . "$file"
}

show_events() {
  need_jq
  local file events
  file="$(resolve_receipt "${1:-}")"
  events="${file%.json}.events.jsonl"
  if [[ -r "$events" ]]; then
    cat "$events"
  fi
}

checkpoint() {
  need_jq
  (( $# > 0 )) || die "checkpoint requires a state"

  local state="$1" summary="" proof="" next="" requested_id="" file events id repo_name now tmp
  shift
  case "$state" in
    todo|working|needs-attention|review|done) ;;
    *) die "invalid checkpoint state: $state" ;;
  esac

  while (( $# > 0 )); do
    case "$1" in
      --proof)
        (( $# >= 2 )) || die "--proof requires text"
        proof="$2"
        shift 2
        ;;
      --next)
        (( $# >= 2 )) || die "--next requires text"
        next="$2"
        shift 2
        ;;
      --id)
        (( $# >= 2 )) || die "--id requires a receipt id"
        requested_id="$2"
        shift 2
        ;;
      *)
        if [[ -n "$summary" ]]; then summary="$summary $1"; else summary="$1"; fi
        shift
        ;;
    esac
  done

  file="$(resolve_receipt "$requested_id")"
  id="$(jq -r '.id' "$file")"
  repo_name="$(jq -r '.repo_name // "task"' "$file")"
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp "$STATE_ROOT/.receipt.XXXXXX")"
  jq \
    --arg state "$state" \
    --arg summary "$summary" \
    --arg proof "$proof" \
    --arg next "$next" \
    --arg now "$now" \
    '.state=$state | .summary=$summary | .proof=$proof | .next=$next | .updated_at=$now' \
    "$file" > "$tmp"
  mv "$tmp" "$file"

  events="${file%.json}.events.jsonl"
  jq -cn \
    --arg at "$now" \
    --arg id "$id" \
    --arg state "$state" \
    --arg summary "$summary" \
    --arg proof "$proof" \
    --arg next "$next" \
    '{version:1,at:$at,id:$id,type:"checkpoint",state:$state,summary:$summary,proof:$proof,next:$next}' \
    >> "$events"

  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1 && [[ -n "${CMUX_WORKSPACE_ID:-}" ]]; then
    cmux workspace status set "$state" >/dev/null 2>&1 || true
    cmux set-status terminal-kit "${summary:-$state}" --workspace "$CMUX_WORKSPACE_ID" >/dev/null 2>&1 || true
    case "$state" in
      needs-attention)
        cmux notify --title "$repo_name needs attention" --body "${summary:-Agent needs input}" >/dev/null 2>&1 || true
        ;;
      done)
        cmux notify --title "$repo_name done" --body "${summary:-Task complete}" >/dev/null 2>&1 || true
        ;;
    esac
  fi

  printf 'terminal-kit: work %s -> %s' "$id" "$state"
  [[ -n "$summary" ]] && printf ': %s' "$summary"
  printf '\n'
}

command_name="${1:-context}"
shift || true
case "$command_name" in
  context)
    if [[ "${1:-}" == --json ]]; then
      context_json
    else
      context_human
    fi
    ;;
  policy)
    show_policy
    ;;
  current)
    show_current "${1:-}"
    ;;
  events)
    show_events "${1:-}"
    ;;
  checkpoint)
    checkpoint "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    printf 'terminal-kit: unknown agent command: %s\n' "$command_name" >&2
    usage >&2
    exit 2
    ;;
esac
