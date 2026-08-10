#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

PROJECTS_ROOT="${TERMINAL_KIT_PROJECTS_ROOT:-$HOME/Projects}"
STATE_ROOT="${TERMINAL_KIT_WORK_STATE_ROOT:-$HOME/.local/state/terminal-kit/work}"
WORKTREE_ROOT="${TERMINAL_KIT_WORKTREE_ROOT:-$HOME/.local/share/terminal-kit/worktrees}"
RECOVERY_REF_ROOT="refs/terminal-kit/recovery"

usage() {
  cat <<'HELP'
Usage:
  terminal-kit work [project-or-reference] [task...]
  terminal-kit work [task...]                 # current repo, or choose a project
  terminal-kit work list
  terminal-kit work show [id|last]
  terminal-kit work path [id|last]
  terminal-kit work undo [id|last]
  terminal-kit work restore [id|last]

Examples:
  tk do fix the failing tests
  tk do smolrunner "finish the next safe runner lifecycle slice"
  tk do ./vmm/src/acpi.rs "clean up the error handling"
  tk do https://github.com/cloud-hypervisor/cloud-hypervisor/issues/8666
  tk do https://github.com/cloud-hypervisor/cloud-hypervisor/pull/123 "finish the review fixes"

Git tasks run in terminal-kit-owned worktrees. Current tracked and untracked
changes are copied into the task checkout while the source checkout stays put.
`work undo` removes only the recorded task checkout after creating hidden Git
recovery refs; `work restore` reconstructs it from those refs.
HELP
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

canonical_file() {
  local directory filename
  directory="$(canonical_dir "$(dirname "$1")")" || return 1
  filename="$(basename "$1")"
  printf '%s/%s\n' "$directory" "$filename"
}

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

safe_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]_.-' '-' \
    | sed 's/^-//; s/-$//'
}

find_project_by_name() {
  local wanted="$1" direct="$PROJECTS_ROOT/$1" marker parent
  local -a matches=()

  if [[ -d "$direct" ]] && git -C "$direct" rev-parse --git-dir >/dev/null 2>&1; then
    canonical_dir "$direct"
    return 0
  fi
  [[ -d "$PROJECTS_ROOT" ]] || return 1

  while IFS= read -r marker; do
    parent="${marker%/.git}"
    [[ "${parent##*/}" == "$wanted" ]] && matches+=("$(canonical_dir "$parent")")
  done < <(find "$PROJECTS_ROOT" -mindepth 2 -maxdepth 4 \( -type d -o -type f \) -name .git -print 2>/dev/null)

  (( ${#matches[@]} == 1 )) || return 1
  printf '%s\n' "${matches[0]}"
}

pick_project() {
  local choices marker selected
  [[ -d "$PROJECTS_ROOT" ]] || die "no project directory at $PROJECTS_ROOT"
  command -v fzf >/dev/null 2>&1 || die "choose a project by name or install fzf"

  choices="$(
    while IFS= read -r marker; do
      printf '%s\n' "${marker%/.git}"
    done < <(find "$PROJECTS_ROOT" -mindepth 2 -maxdepth 4 \( -type d -o -type f \) -name .git -print 2>/dev/null)
  )"
  [[ -n "$choices" ]] || die "no Git projects found beneath $PROJECTS_ROOT"
  selected="$(printf '%s\n' "$choices" | sort -u | fzf --prompt='project> ' --height=40% --reverse)" || return 1
  [[ -n "$selected" ]] || return 1
  canonical_dir "$selected"
}

is_remote_target() {
  case "$1" in
    http://*|https://*|ssh://*|git@*:*) return 0 ;;
  esac
  [[ "$1" == */* && "$1" != /* && "$1" != ./* && "$1" != ../* ]]
}

remote_repo_name() {
  local value="${1%/}"
  value="${value%.git}"
  printf '%s\n' "${value##*/}"
}

ROUTED_TARGET=""
ROUTED_REFERENCE=""
route_reference() {
  local raw="$1" expanded parent repo_root rest owner remainder repo tail shorthand
  ROUTED_TARGET=""
  ROUTED_REFERENCE=""
  expanded="$(expand_path "$raw")"

  if [[ -f "$expanded" ]]; then
    parent="$(dirname "$expanded")"
    repo_root="$(git -C "$parent" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$repo_root" ]]; then
      ROUTED_TARGET="$(canonical_dir "$repo_root")"
    else
      ROUTED_TARGET="$(canonical_dir "$parent")"
    fi
    ROUTED_REFERENCE="$(canonical_file "$expanded")"
    return 0
  fi

  case "$raw" in
    https://github.com/*)
      rest="${raw#https://github.com/}"
      owner="${rest%%/*}"
      [[ "$rest" == */* ]] || return 1
      remainder="${rest#*/}"
      repo="${remainder%%/*}"
      repo="${repo%.git}"
      [[ -n "$owner" && -n "$repo" ]] || return 1
      if [[ "$remainder" == */* ]]; then
        tail="${remainder#*/}"
        [[ -n "$tail" ]] || return 1
        ROUTED_TARGET="$owner/$repo"
        ROUTED_REFERENCE="$raw"
        return 0
      fi
      ;;
  esac

  if [[ "$raw" == *'#'* ]]; then
    shorthand="${raw%%#*}"
    if [[ "$shorthand" == */* && "$shorthand" != /* && "$shorthand" != ./* && "$shorthand" != ../* ]]; then
      ROUTED_TARGET="$shorthand"
      ROUTED_REFERENCE="$raw"
      return 0
    fi
  fi
  return 1
}

compose_reference_prompt() {
  local reference="$1" requested="$2"
  [[ -n "$reference" ]] || {
    printf '%s' "$requested"
    return 0
  }
  if [[ -n "$requested" ]]; then
    printf 'Primary reference: %s\n\nRequested outcome:\n%s' "$reference" "$requested"
  else
    printf 'Use this as the primary reference: %s\nInspect its current state with the repository-native and GitHub tools available to you, infer the appropriate implementation work, carry it through, and run the relevant checks.' "$reference"
  fi
}

RESOLVED_PATH=""
CLONED=false
resolve_target() {
  local raw="$1" expanded local_match name destination
  expanded="$(expand_path "$raw")"

  if [[ -d "$expanded" ]]; then
    RESOLVED_PATH="$(canonical_dir "$expanded")"
    return 0
  fi
  if local_match="$(find_project_by_name "$raw" 2>/dev/null)"; then
    RESOLVED_PATH="$local_match"
    return 0
  fi

  is_remote_target "$raw" || die "cannot resolve project: $raw"
  name="$(remote_repo_name "$raw")"
  [[ -n "$name" ]] || die "cannot derive repository name from: $raw"
  mkdir -p "$PROJECTS_ROOT"
  destination="$PROJECTS_ROOT/$name"

  if [[ -e "$destination" ]]; then
    if [[ -d "$destination" ]] && git -C "$destination" rev-parse --git-dir >/dev/null 2>&1; then
      RESOLVED_PATH="$(canonical_dir "$destination")"
      return 0
    fi
    die "clone destination already exists and is not a Git repository: $destination"
  fi

  log "cloning $raw into ${destination/#$HOME/\~}"
  if command -v gh >/dev/null 2>&1 \
    && [[ "$raw" == *github.com* || "$raw" != *://* && "$raw" != git@* ]]; then
    gh repo clone "$raw" "$destination"
  else
    git clone "$raw" "$destination"
  fi
  CLONED=true
  RESOLVED_PATH="$(canonical_dir "$destination")"
}

current_git_root() {
  git rev-parse --show-toplevel 2>/dev/null || true
}

worktree_dirty() {
  [[ -n "$(git -C "$1" status --porcelain --untracked-files=all)" ]]
}

# Create an object-only snapshot using an alternate index. It captures tracked
# and non-ignored untracked files without touching the user's index, branch,
# stash list, or working tree.
snapshot_checkout() {
  local checkout="$1" parent="$2" index tree commit
  index="$(mktemp -t terminal-kit-index.XXXXXX)"
  rm -f "$index"

  if ! GIT_INDEX_FILE="$index" git -C "$checkout" read-tree "$parent" \
    || ! GIT_INDEX_FILE="$index" git -C "$checkout" add -A -- .; then
    rm -f "$index"
    return 1
  fi
  tree="$(GIT_INDEX_FILE="$index" git -C "$checkout" write-tree)" || {
    rm -f "$index"
    return 1
  }
  rm -f "$index"

  commit="$(
    printf 'terminal-kit recovery snapshot\n' \
      | env \
          GIT_AUTHOR_NAME=terminal-kit \
          GIT_AUTHOR_EMAIL=terminal-kit@localhost \
          GIT_COMMITTER_NAME=terminal-kit \
          GIT_COMMITTER_EMAIL=terminal-kit@localhost \
          git -C "$checkout" commit-tree "$tree" -p "$parent"
  )" || return 1
  printf '%s\n' "$commit"
}

apply_snapshot_delta() {
  local repo="$1" destination="$2" base="$3" snapshot="$4"
  git -C "$repo" diff --binary "$base" "$snapshot" -- \
    | git -C "$destination" apply --whitespace=nowarn
}

seed_worktree_from_checkout() {
  local source="$1" destination="$2" base="$3" snapshot
  snapshot="$(snapshot_checkout "$source" "$base")" || return 1
  apply_snapshot_delta "$source" "$destination" "$base" "$snapshot"
}

select_agent() {
  local candidate
  if [[ -n "${TERMINAL_KIT_AGENT:-}" ]]; then
    printf '%s\n' "$TERMINAL_KIT_AGENT"
    return 0
  fi
  for candidate in codex claude opencode pi; do
    command -v "$candidate" >/dev/null 2>&1 && {
      printf '%s\n' "$candidate"
      return 0
    }
  done
  printf '%s\n' codex
}

agent_policy_prompt() {
  local user_prompt="$1" seeded_dirty="$2"
  cat <<EOF
Work autonomously in this repository and own the ordinary implementation loop.
Read repository guidance such as AGENTS.md, CLAUDE.md, CONTRIBUTING.md, and repo-native bootstrap/check scripts before changing code. Prefer the commands and workflows the repository already defines. Inspect the current state, make the requested changes, chain the relevant checks yourself, and finish with a concise summary of edits, checks, and any blocker.

Preserve existing user work and stay inside this task checkout. Ordinary repository edits, local tests, formatting, dependency commands, branches, commits, and pull-request preparation are within scope. Stop and ask before privileged host changes, credential or account changes, destructive external actions, releases/publication, paid-resource changes, or irreversible data migrations.
EOF
  if [[ "$seeded_dirty" == true ]]; then
    cat <<'EOF'

This task checkout was seeded from local tracked and untracked changes in the source checkout. Treat those changes as user work and preserve their intent.
EOF
  fi
  cat <<EOF

User task:
$user_prompt
EOF
}

write_receipt() {
  local file="$1" id="$2" created_at="$3" target="$4" repo_name="$5"
  local repo_root="$6" work_path="$7" branch="$8" base_sha="$9"
  shift 9
  local agent="$1" launcher="$2" prompt="$3" reference="$4"
  local cloned="$5" seeded_dirty="$6" mode="$7" tmp

  mkdir -p "$STATE_ROOT"
  tmp="$(mktemp "$STATE_ROOT/.receipt.XXXXXX")"
  jq -n \
    --arg id "$id" --arg created_at "$created_at" --arg target "$target" \
    --arg repo_name "$repo_name" --arg repo_root "$repo_root" --arg work_path "$work_path" \
    --arg branch "$branch" --arg base_sha "$base_sha" --arg agent "$agent" \
    --arg launcher "$launcher" --arg prompt "$prompt" --arg reference "$reference" --arg mode "$mode" \
    --argjson cloned "$cloned" --argjson seeded_dirty "$seeded_dirty" \
    '{version:1,id:$id,state:"prepared",created_at:$created_at,target:$target,
      repo_name:$repo_name,repo_root:$repo_root,work_path:$work_path,branch:$branch,
      base_sha:$base_sha,agent:$agent,launcher:$launcher,prompt:$prompt,reference:$reference,
      mode:$mode,cloned:$cloned,seeded_dirty:$seeded_dirty}' > "$tmp"
  mv "$tmp" "$file"
  printf '%s\n' "$id" > "$STATE_ROOT/last"
}

update_receipt() {
  local file="$1" filter="$2" tmp
  shift 2
  tmp="$(mktemp "$STATE_ROOT/.receipt.XXXXXX")"
  jq "$@" "$filter" "$file" > "$tmp"
  mv "$tmp" "$file"
}

update_receipt_state() {
  local file="$1" state="$2" field="$3" now
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  update_receipt "$file" '.state=$state | .[$field]=$now' \
    --arg state "$state" --arg field "$field" --arg now "$now"
}

receipt_for() {
  local requested="${1:-last}" id file
  if [[ "$requested" == last ]]; then
    [[ -r "$STATE_ROOT/last" ]] || die "no terminal-kit work receipt yet"
    id="$(tr -d '[:space:]' < "$STATE_ROOT/last")"
  else
    id="$requested"
  fi
  file="$STATE_ROOT/$id.json"
  [[ -r "$file" ]] || die "unknown work receipt: $id"
  printf '%s\n' "$file"
}

list_work() {
  local file rows="" count=0
  [[ -d "$STATE_ROOT" ]] || {
    printf 'No terminal-kit work sessions yet.\n'
    return 0
  }
  for file in "$STATE_ROOT"/*.json; do
    [[ -r "$file" ]] || continue
    count=$((count + 1))
    rows="${rows}$(jq -r '[.id,.state,.repo_name,.agent,.created_at] | @tsv' "$file")"$'\n'
  done
  (( count > 0 )) || {
    printf 'No terminal-kit work sessions yet.\n'
    return 0
  }

  printf '%-24s %-16s %-18s %-9s %s\n' ID STATE PROJECT AGENT CREATED
  printf '%s' "$rows" | sort -r | while IFS=$'\t' read -r id state project agent created; do
    [[ -n "$id" ]] || continue
    printf '%-24s %-16s %-18s %-9s %s\n' "$id" "$state" "$project" "$agent" "$created"
  done
}

show_work() {
  cat "$(receipt_for "${1:-last}")"
}

show_path() {
  jq -r '.work_path' "$(receipt_for "${1:-last}")"
}

undo_work() {
  local file id mode repo_root work_path canonical_work_path branch state head_oid
  local snapshot_oid="" recovery_head recovery_snapshot now

  file="$(receipt_for "${1:-last}")"
  id="$(jq -r '.id' "$file")"
  mode="$(jq -r '.mode' "$file")"
  repo_root="$(jq -r '.repo_root' "$file")"
  work_path="$(jq -r '.work_path' "$file")"
  branch="$(jq -r '.branch' "$file")"
  state="$(jq -r '.state' "$file")"

  [[ "$mode" == worktree ]] || die "receipt $id does not own a disposable worktree"
  [[ "$state" != undone ]] || {
    log "work $id is already undone"
    return 0
  }
  [[ -d "$repo_root" ]] || die "source repository is missing: $repo_root"
  [[ -d "$work_path" ]] || die "owned worktree is missing: $work_path"

  canonical_work_path="$(canonical_dir "$work_path")"
  [[ "$(canonical_dir "$(git -C "$work_path" rev-parse --show-toplevel 2>/dev/null)")" == "$canonical_work_path" ]] \
    || die "refusing to remove path that is no longer the recorded worktree: $work_path"
  [[ "$(git -C "$work_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$branch" ]] \
    || die "refusing to remove worktree because its branch no longer matches the receipt"

  head_oid="$(git -C "$work_path" rev-parse HEAD)"
  recovery_head="$RECOVERY_REF_ROOT/$id/head"
  recovery_snapshot="$RECOVERY_REF_ROOT/$id/snapshot"
  git -C "$repo_root" update-ref "$recovery_head" "$head_oid"

  if worktree_dirty "$work_path"; then
    snapshot_oid="$(snapshot_checkout "$work_path" "$head_oid")" \
      || die "could not create a recovery snapshot; leaving the worktree in place"
    git -C "$repo_root" update-ref "$recovery_snapshot" "$snapshot_oid"
  else
    git -C "$repo_root" update-ref -d "$recovery_snapshot" >/dev/null 2>&1 || true
  fi

  git -C "$repo_root" worktree remove --force "$work_path"
  git -C "$repo_root" branch -D "$branch" >/dev/null 2>&1 || true

  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  update_receipt "$file" \
    '.state="undone" | .undone_at=$now | .recovery_head_ref=$head | .recovery_snapshot_ref=$snapshot | .recovery_snapshot_oid=$snapshot_oid' \
    --arg now "$now" --arg head "$recovery_head" --arg snapshot "$recovery_snapshot" --arg snapshot_oid "$snapshot_oid"
  log "undid work $id; hidden recovery refs are keeping the task recoverable"
}

restore_work() {
  local file id mode repo_root work_path branch state recovery_head recovery_snapshot now
  file="$(receipt_for "${1:-last}")"
  id="$(jq -r '.id' "$file")"
  mode="$(jq -r '.mode' "$file")"
  repo_root="$(jq -r '.repo_root' "$file")"
  work_path="$(jq -r '.work_path' "$file")"
  branch="$(jq -r '.branch' "$file")"
  state="$(jq -r '.state' "$file")"
  recovery_head="$(jq -r '.recovery_head_ref // empty' "$file")"
  recovery_snapshot="$(jq -r '.recovery_snapshot_ref // empty' "$file")"

  [[ "$mode" == worktree ]] || die "receipt $id is not a disposable worktree"
  [[ "$state" == undone ]] || die "work $id is not currently undone"
  [[ -n "$recovery_head" ]] || die "receipt has no recovery head ref"
  git -C "$repo_root" show-ref --verify --quiet "$recovery_head" \
    || die "recovery head ref is missing: $recovery_head"
  [[ ! -e "$work_path" ]] || die "restore path already exists: $work_path"
  git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" \
    && die "restore branch already exists: $branch"

  git -C "$repo_root" branch "$branch" "$recovery_head"
  if ! git -C "$repo_root" worktree add "$work_path" "$branch"; then
    git -C "$repo_root" branch -D "$branch" >/dev/null 2>&1 || true
    return 1
  fi
  work_path="$(canonical_dir "$work_path")"

  if [[ -n "$recovery_snapshot" ]] && git -C "$repo_root" show-ref --verify --quiet "$recovery_snapshot"; then
    if ! apply_snapshot_delta "$repo_root" "$work_path" "$recovery_head" "$recovery_snapshot"; then
      now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      update_receipt "$file" '.state="restore-conflict" | .restore_attempted_at=$now' --arg now "$now"
      die "recovery changes conflicted while restoring; the worktree was kept for manual resolution"
    fi
  fi

  update_receipt_state "$file" restored restored_at
  log "restored work $id at ${work_path/#$HOME/\~}"
  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
    cmux new-workspace --name "$(jq -r '.repo_name' "$file") · restored" --cwd "$work_path" >/dev/null 2>&1 || true
  fi
}

launch_agent() {
  local agent="$1" work_path="$2" title="$3" prompt="$4" quoted command_text

  if command -v cmux-chat >/dev/null 2>&1 \
    && command -v cmux >/dev/null 2>&1 \
    && cmux ping >/dev/null 2>&1; then
    local -a chat_args=(cmux-chat -p "$agent" -C "$work_path")
    [[ "${TERMINAL_KIT_AGENT_APPROVAL:-auto}" == ask ]] && chat_args+=(--no-auto-approve)
    [[ -n "$prompt" ]] && chat_args+=("$prompt")
    "${chat_args[@]}"
    return 0
  fi

  if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
    if [[ -z "$prompt" ]]; then
      cmux new-workspace --name "$title" --cwd "$work_path"
      return 0
    fi
    if ! command -v "$agent" >/dev/null 2>&1; then
      cmux new-workspace --name "$title" --cwd "$work_path"
      warn "agent '$agent' is unavailable; opened the task worktree without launching it"
      return 0
    fi

    quoted="$(printf '%s' "$prompt" | jq -Rrs @sh)"
    case "$agent" in
      codex) command_text="codex --yolo -- $quoted" ;;
      claude) command_text="claude --dangerously-skip-permissions -- $quoted" ;;
      opencode) command_text="opencode --prompt $quoted" ;;
      pi) command_text="pi -- $quoted" ;;
      *)
        cmux new-workspace --name "$title" --cwd "$work_path"
        warn "unknown agent '$agent'; opened the task worktree without launching it"
        return 0
        ;;
    esac
    cmux new-workspace --name "$title" --cwd "$work_path" --command "$command_text; exec /bin/zsh -l"
    return 0
  fi

  [[ -n "$prompt" ]] || {
    printf '%s\n' "$work_path"
    warn "cmux is unavailable; open the path above and start your agent there"
    return 0
  }
  command -v "$agent" >/dev/null 2>&1 || die "cmux is unavailable and agent '$agent' is not installed"
  case "$agent" in
    codex) (cd "$work_path" && codex --yolo -- "$prompt") ;;
    claude) (cd "$work_path" && claude --dangerously-skip-permissions -- "$prompt") ;;
    opencode) (cd "$work_path" && opencode --prompt "$prompt") ;;
    pi) (cd "$work_path" && pi -- "$prompt") ;;
    *) die "cmux is unavailable and agent '$agent' has no terminal-kit launcher" ;;
  esac
}

start_work() {
  need_command git
  need_command jq

  local current_repo first candidate_match target prompt="" reference="" source_path repo_root repo_name repo_slug
  local id created_at branch work_path base_sha agent launcher seeded_dirty=false mode=worktree
  local full_prompt="" receipt title expanded
  current_repo="$(current_git_root)"

  if (( $# == 0 )); then
    [[ -n "$current_repo" ]] && target="$current_repo" || target="$(pick_project)"
  else
    first="$1"
    candidate_match=""
    expanded="$(expand_path "$first")"
    if route_reference "$first"; then
      target="$ROUTED_TARGET"
      reference="$ROUTED_REFERENCE"
      shift
      prompt="$*"
    elif [[ -d "$expanded" ]]; then
      target="$first"; shift; prompt="$*"
    elif candidate_match="$(find_project_by_name "$first" 2>/dev/null)"; then
      target="$candidate_match"; shift; prompt="$*"
    elif is_remote_target "$first"; then
      target="$first"; shift; prompt="$*"
    elif [[ -n "$current_repo" ]]; then
      target="$current_repo"; prompt="$*"
    else
      target="$(pick_project)"; prompt="$*"
    fi
  fi

  prompt="$(compose_reference_prompt "$reference" "$prompt")"
  resolve_target "$target"
  source_path="$RESOLVED_PATH"
  if repo_root="$(git -C "$source_path" rev-parse --show-toplevel 2>/dev/null)"; then
    repo_root="$(canonical_dir "$repo_root")"
  else
    repo_root="$source_path"
    mode=direct
  fi
  repo_name="${repo_root##*/}"
  repo_slug="$(safe_slug "$repo_name")"
  [[ -n "$repo_slug" ]] || repo_slug=project

  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  id="$(date '+%Y%m%d-%H%M%S')-$$-${RANDOM:-0}"
  agent="$(select_agent)"
  launcher=terminal
  command -v cmux-chat >/dev/null 2>&1 && launcher=cmux-chat
  mkdir -p "$STATE_ROOT" "$WORKTREE_ROOT/$repo_slug"
  receipt="$STATE_ROOT/$id.json"

  if [[ "$mode" == worktree ]]; then
    base_sha="$(git -C "$repo_root" rev-parse HEAD)"
    branch="tk/$repo_slug-$id"
    work_path="$WORKTREE_ROOT/$repo_slug/$id"
    worktree_dirty "$repo_root" && seeded_dirty=true

    git -C "$repo_root" worktree add -b "$branch" "$work_path" HEAD
    work_path="$(canonical_dir "$work_path")"
    if [[ "$seeded_dirty" == true ]] \
      && ! seed_worktree_from_checkout "$repo_root" "$work_path" "$base_sha"; then
      git -C "$repo_root" worktree remove --force "$work_path" >/dev/null 2>&1 || true
      git -C "$repo_root" branch -D "$branch" >/dev/null 2>&1 || true
      die "could not copy the current checkout changes into the task worktree"
    fi
  else
    base_sha=""; branch=""; work_path="$repo_root"
  fi

  [[ -n "$prompt" ]] && full_prompt="$(agent_policy_prompt "$prompt" "$seeded_dirty")"
  write_receipt "$receipt" "$id" "$created_at" "$target" "$repo_name" "$repo_root" \
    "$work_path" "$branch" "$base_sha" "$agent" "$launcher" "$prompt" "$reference" \
    "$CLONED" "$seeded_dirty" "$mode"

  title="$repo_name · work"
  log "work $id: ${work_path/#$HOME/\~}"
  [[ -n "$reference" ]] && log "reference: $reference"
  [[ "$seeded_dirty" == true ]] && log "copied current checkout changes into the isolated worktree"
  if launch_agent "$agent" "$work_path" "$title" "$full_prompt"; then
    update_receipt_state "$receipt" launched launched_at
  else
    warn "agent launch failed; the prepared worktree and receipt were kept"
    return 1
  fi
}

command_name="${1:-start}"
case "$command_name" in
  list) shift; list_work "$@" ;;
  show) shift; show_work "${1:-last}" ;;
  path) shift; show_path "${1:-last}" ;;
  undo) shift; undo_work "${1:-last}" ;;
  restore) shift; restore_work "${1:-last}" ;;
  help|-h|--help) usage ;;
  start) shift || true; start_work "$@" ;;
  *) start_work "$@" ;;
esac
