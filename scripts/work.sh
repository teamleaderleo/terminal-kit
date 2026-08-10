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
  terminal-kit work [project-or-url] [task...]
  terminal-kit work [task...]                 # current repo, or choose a project
  terminal-kit work list
  terminal-kit work show [id|last]
  terminal-kit work path [id|last]
  terminal-kit work undo [id|last]
  terminal-kit work restore [id|last]

Examples:
  tk work smolrunner "finish the next safe runner lifecycle slice"
  tk work https://github.com/cloud-hypervisor/cloud-hypervisor "fix the ACPI errors"
  tk work fix the failing tests               # from inside a repository
  tk work                                     # open an agent session for the current repo

A Git task runs in a terminal-kit-owned worktree. If the current checkout has
local tracked or untracked changes, their contents are copied into the task
worktree while the original checkout stays untouched. `work undo` stores hidden
Git recovery refs before removing the owned worktree; `work restore` recreates it.
HELP
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

safe_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]_.-' '-' \
    | sed 's/^-//; s/-$//'
}

find_project_by_name() {
  local wanted="$1"
  local direct="$PROJECTS_ROOT/$wanted"
  local marker parent
  local -a matches=()

  if [[ -d "$direct" ]] && git -C "$direct" rev-parse --git-dir >/dev/null 2>&1; then
    canonical_dir "$direct"
    return 0
  fi

  [[ -d "$PROJECTS_ROOT" ]] || return 1
  while IFS= read -r marker; do
    parent="${marker%/.git}"
    if [[ "${parent##*/}" == "$wanted" ]]; then
      matches+=("$(canonical_dir "$parent")")
    fi
  done < <(find "$PROJECTS_ROOT" -mindepth 2 -maxdepth 4 \( -type d -o -type f \) -name .git -print 2>/dev/null)

  if (( ${#matches[@]} == 1 )); then
    printf '%s\n' "${matches[0]}"
    return 0
  fi
  return 1
}

pick_project() {
  local choices selected marker
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

RESOLVED_PATH=""
CLONED=false
resolve_target() {
  local raw="$1"
  local expanded local_match name destination
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

copy_untracked_files() {
  local source_root="$1"
  local destination_root="$2"
  local relative source destination

  while IFS= read -r -d '' relative; do
    source="$source_root/$relative"
    destination="$destination_root/$relative"
    mkdir -p "$(dirname "$destination")"
    if [[ -L "$source" ]]; then
      ln -s "$(readlink "$source")" "$destination"
    else
      cp -p "$source" "$destination"
    fi
  done < <(git -C "$source_root" ls-files --others --exclude-standard -z)
}

seed_worktree_from_checkout() {
  local source_root="$1"
  local destination_root="$2"
  local patch
  patch="$(mktemp -t terminal-kit-work.XXXXXX)"
  git -C "$source_root" diff --binary HEAD -- > "$patch"
  if [[ -s "$patch" ]]; then
    if ! git -C "$destination_root" apply --whitespace=nowarn "$patch"; then
      rm -f "$patch"
      return 1
    fi
  fi
  rm -f "$patch"
  copy_untracked_files "$source_root" "$destination_root"
}

select_agent() {
  local candidate
  if [[ -n "${TERMINAL_KIT_AGENT:-}" ]]; then
    printf '%s\n' "$TERMINAL_KIT_AGENT"
    return 0
  fi
  for candidate in codex claude opencode pi; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' codex
}

agent_policy_prompt() {
  local user_prompt="$1"
  local seeded_dirty="$2"
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
  local file="$1"
  local id="$2"
  local created_at="$3"
  local target="$4"
  local repo_name="$5"
  local repo_root="$6"
  local work_path="$7"
  local branch="$8"
  local base_sha="$9"
  shift 9
  local agent="$1"
  local launcher="$2"
  local prompt="$3"
  local cloned="$4"
  local seeded_dirty="$5"
  local mode="$6"
  local tmp

  mkdir -p "$STATE_ROOT"
  tmp="$(mktemp "$STATE_ROOT/.receipt.XXXXXX")"
  jq -n \
    --arg id "$id" \
    --arg created_at "$created_at" \
    --arg target "$target" \
    --arg repo_name "$repo_name" \
    --arg repo_root "$repo_root" \
    --arg work_path "$work_path" \
    --arg branch "$branch" \
    --arg base_sha "$base_sha" \
    --arg agent "$agent" \
    --arg launcher "$launcher" \
    --arg prompt "$prompt" \
    --arg mode "$mode" \
    --argjson cloned "$cloned" \
    --argjson seeded_dirty "$seeded_dirty" \
    '{
      version: 1,
      id: $id,
      state: "prepared",
      created_at: $created_at,
      target: $target,
      repo_name: $repo_name,
      repo_root: $repo_root,
      work_path: $work_path,
      branch: $branch,
      base_sha: $base_sha,
      agent: $agent,
      launcher: $launcher,
      prompt: $prompt,
      mode: $mode,
      cloned: $cloned,
      seeded_dirty: $seeded_dirty
    }' > "$tmp"
  mv "$tmp" "$file"
  printf '%s\n' "$id" > "$STATE_ROOT/last"
}

update_receipt_state() {
  local file="$1"
  local state="$2"
  local timestamp_field="$3"
  local now tmp
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp "$STATE_ROOT/.receipt.XXXXXX")"
  jq --arg state "$state" --arg field "$timestamp_field" --arg now "$now" \
    '.state=$state | .[$field]=$now' "$file" > "$tmp"
  mv "$tmp" "$file"
}

receipt_for() {
  local requested="${1:-last}"
  local id file
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
  if (( count == 0 )); then
    printf 'No terminal-kit work sessions yet.\n'
    return 0
  fi
  printf '%-24s %-16s %-18s %-9s %s\n' ID STATE PROJECT AGENT CREATED
  printf '%s' "$rows" | sort -r | while IFS=$'\t' read -r id state project agent created; do
    [[ -n "$id" ]] || continue
    printf '%-24s %-16s %-18s %-9s %s\n' "$id" "$state" "$project" "$agent" "$created"
  done
}

show_work() {
  local file
  file="$(receipt_for "${1:-last}")"
  cat "$file"
}

show_path() {
  local file
  file="$(receipt_for "${1:-last}")"
  jq -r '.work_path' "$file"
}

undo_work() {
  local file id mode repo_root work_path branch state head_oid stash_oid="" recovery_head recovery_stash tmp
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
  [[ "$(git -C "$work_path" rev-parse --show-toplevel 2>/dev/null || true)" == "$work_path" ]] \
    || die "refusing to remove path that is no longer the recorded worktree: $work_path"
  [[ "$(git -C "$work_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$branch" ]] \
    || die "refusing to remove worktree because its branch no longer matches the receipt"

  if [[ -n "$(git -C "$work_path" status --porcelain)" ]]; then
    git -C "$work_path" stash push --include-untracked -m "terminal-kit recovery $id" >/dev/null
    stash_oid="$(git -C "$repo_root" rev-parse refs/stash)"
  fi
  [[ -z "$(git -C "$work_path" status --porcelain)" ]] \
    || die "worktree still has uncaptured changes; leaving it in place"

  head_oid="$(git -C "$work_path" rev-parse HEAD)"
  recovery_head="$RECOVERY_REF_ROOT/$id/head"
  recovery_stash="$RECOVERY_REF_ROOT/$id/stash"
  git -C "$repo_root" update-ref "$recovery_head" "$head_oid"
  if [[ -n "$stash_oid" ]]; then
    git -C "$repo_root" update-ref "$recovery_stash" "$stash_oid"
  else
    git -C "$repo_root" update-ref -d "$recovery_stash" >/dev/null 2>&1 || true
  fi

  git -C "$repo_root" worktree remove --force "$work_path"
  git -C "$repo_root" branch -D "$branch" >/dev/null 2>&1 || true

  tmp="$(mktemp "$STATE_ROOT/.receipt.XXXXXX")"
  jq \
    --arg now "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg recovery_head "$recovery_head" \
    --arg recovery_stash "$recovery_stash" \
    --arg stash_oid "$stash_oid" \
    '.state="undone" | .undone_at=$now | .recovery_head_ref=$recovery_head | .recovery_stash_ref=$recovery_stash | .recovery_stash_oid=$stash_oid' \
    "$file" > "$tmp"
  mv "$tmp" "$file"
  log "undid work $id; recovery refs kept in the source repository"
}

restore_work() {
  local file id mode repo_root work_path branch state recovery_head recovery_stash stash_oid="" tmp
  file="$(receipt_for "${1:-last}")"
  id="$(jq -r '.id' "$file")"
  mode="$(jq -r '.mode' "$file")"
  repo_root="$(jq -r '.repo_root' "$file")"
  work_path="$(jq -r '.work_path' "$file")"
  branch="$(jq -r '.branch' "$file")"
  state="$(jq -r '.state' "$file")"
  recovery_head="$(jq -r '.recovery_head_ref // empty' "$file")"
  recovery_stash="$(jq -r '.recovery_stash_ref // empty' "$file")"

  [[ "$mode" == worktree ]] || die "receipt $id is not a disposable worktree"
  [[ "$state" == undone ]] || die "work $id is not currently undone"
  [[ -n "$recovery_head" ]] || die "receipt has no recovery head ref"
  git -C "$repo_root" show-ref --verify --quiet "$recovery_head" \
    || die "recovery head ref is missing: $recovery_head"
  [[ ! -e "$work_path" ]] || die "restore path already exists: $work_path"
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    die "restore branch already exists: $branch"
  fi

  git -C "$repo_root" branch "$branch" "$recovery_head"
  if ! git -C "$repo_root" worktree add "$work_path" "$branch"; then
    git -C "$repo_root" branch -D "$branch" >/dev/null 2>&1 || true
    return 1
  fi

  if [[ -n "$recovery_stash" ]] && git -C "$repo_root" show-ref --verify --quiet "$recovery_stash"; then
    stash_oid="$(git -C "$repo_root" rev-parse "$recovery_stash")"
    if ! git -C "$work_path" stash apply "$stash_oid"; then
      tmp="$(mktemp "$STATE_ROOT/.receipt.XXXXXX")"
      jq --arg now "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '.state="restore-conflict" | .restore_attempted_at=$now' "$file" > "$tmp"
      mv "$tmp" "$file"
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
  local agent="$1"
  local work_path="$2"
  local title="$3"
  local prompt="$4"
  local quoted command_text

  if command -v cmux-chat >/dev/null 2>&1 \
    && command -v cmux >/dev/null 2>&1 \
    && cmux ping >/dev/null 2>&1; then
    local -a chat_args=(cmux-chat -p "$agent" -C "$work_path")
    if [[ "${TERMINAL_KIT_AGENT_APPROVAL:-auto}" == ask ]]; then
      chat_args+=(--no-auto-approve)
    fi
    if [[ -n "$prompt" ]]; then
      chat_args+=("$prompt")
    fi
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
    command_text="$command_text; exec /bin/zsh -l"
    cmux new-workspace --name "$title" --cwd "$work_path" --command "$command_text"
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

  local current_repo first candidate_match target prompt="" source_path repo_root repo_name repo_slug
  local id created_at branch work_path base_sha agent launcher seeded_dirty=false mode=worktree
  local source_status="" full_prompt="" receipt title
  current_repo="$(current_git_root)"

  if (( $# == 0 )); then
    if [[ -n "$current_repo" ]]; then
      target="$current_repo"
    else
      target="$(pick_project)"
    fi
  else
    first="$1"
    candidate_match=""
    if [[ -d "$(expand_path "$first")" ]]; then
      target="$first"
      shift
      prompt="$*"
    elif candidate_match="$(find_project_by_name "$first" 2>/dev/null)"; then
      target="$candidate_match"
      shift
      prompt="$*"
    elif is_remote_target "$first"; then
      target="$first"
      shift
      prompt="$*"
    elif [[ -n "$current_repo" ]]; then
      target="$current_repo"
      prompt="$*"
    else
      target="$(pick_project)"
      prompt="$*"
    fi
  fi

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
    source_status="$(git -C "$repo_root" status --porcelain)"
    [[ -n "$source_status" ]] && seeded_dirty=true

    git -C "$repo_root" worktree add -b "$branch" "$work_path" HEAD
    if [[ "$seeded_dirty" == true ]]; then
      if ! seed_worktree_from_checkout "$repo_root" "$work_path"; then
        git -C "$repo_root" worktree remove --force "$work_path" >/dev/null 2>&1 || true
        git -C "$repo_root" branch -D "$branch" >/dev/null 2>&1 || true
        die "could not copy the current checkout changes into the task worktree"
      fi
    fi
  else
    base_sha=""
    branch=""
    work_path="$repo_root"
  fi

  if [[ -n "$prompt" ]]; then
    full_prompt="$(agent_policy_prompt "$prompt" "$seeded_dirty")"
  fi

  write_receipt "$receipt" "$id" "$created_at" "$target" "$repo_name" "$repo_root" \
    "$work_path" "$branch" "$base_sha" "$agent" "$launcher" "$prompt" "$CLONED" "$seeded_dirty" "$mode"

  title="$repo_name · work"
  log "work $id: ${work_path/#$HOME/\~}"
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
  list)
    shift
    list_work "$@"
    ;;
  show)
    shift
    show_work "${1:-last}"
    ;;
  path)
    shift
    show_path "${1:-last}"
    ;;
  undo)
    shift
    undo_work "${1:-last}"
    ;;
  restore)
    shift
    restore_work "${1:-last}"
    ;;
  help|-h|--help)
    usage
    ;;
  start)
    shift || true
    start_work "$@"
    ;;
  *)
    start_work "$@"
    ;;
esac
