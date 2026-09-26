#!/usr/bin/env bash
# Shared helpers for work.sh and agent.sh: task receipts and the agent brief.

STATE_ROOT="${TERMINAL_KIT_WORK_STATE_ROOT:-$HOME/.local/state/terminal-kit/work}"

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# Print the receipt path for an id or "last"; return 1 when there is none.
find_receipt() {
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

# The standing brief every tk do agent gets, and what `tk agent policy` prints.
agent_brief() {
  cat <<'EOF_BRIEF'
You are working in a terminal-kit task checkout (a Git worktree); the source checkout is untouched.
- Read the repository's own guidance (AGENTS.md, CLAUDE.md, CONTRIBUTING.md) and use its bootstrap and check commands.
- Own the outcome: implement, run the checks, review your diff, and commit. Pushing and opening or merging PRs is fine when the remote is the operator's and repository policy allows it.
- Preserve existing user work and running terminal processes.
- Ask first before: spending money, exposing or rotating secrets, widening access, publishing or contacting anyone as the operator, destroying non-test data, privileged host changes, or irreversible migrations.
- When exact values (GitHub data, command output) must leave the terminal, use machine-readable output such as `gh ... --json ... --jq ...`, not terminal tables.
- `terminal-kit agent context --json` shows this task's receipt. Record progress with `terminal-kit agent checkpoint <working|needs-attention|review|done> "summary" [--proof text] [--next text]`.
- Finish with what changed, the checks you ran, and anything left, so a fresh agent could continue without this chat.
EOF_BRIEF
}
