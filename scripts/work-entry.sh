#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/scripts/work.sh"

case "${1:-}" in
  list|show|path|undo|restore|help|-h|--help)
    exec /bin/bash "$WORK" "$@"
    ;;
  start)
    shift
    ;;
esac

read -r -d '' AGENT_BOOTSTRAP <<'BOOTSTRAP' || true

Agent operating note from terminal-kit:
- If `terminal-kit agent context --json` is available, read it before substantive work. It contains the current repository/task receipt, repository guidance, available agent tools, cmux context, and the standing machine policy.
- Prefer the target repository's own guidance and commands. Compose its AGENTS.md/CLAUDE.md/STENSIBLY.md, bootstrap scripts, package scripts, Makefiles, and CI checks instead of inventing another workflow.
- If the operator supplied only a repository/reference or no separate outcome, inspect current state and choose the highest-value bounded coherent outcome you can actually carry through.
- Own a meaningful outcome and continue through covered executable steps. Ordinary reversible repository work may proceed through implementation, checks, self-review, commits, and operator-controlled integration when repository policy and permissions allow.
- Treat terminal tables, colours, and visual wrapping as presentation rather than exact evidence. When GitHub values or other machine facts need to leave the terminal, prefer compact JSON/JQ/template output on the first attempt. If the operator must run a command and return its result, request output that survives clipboard/chat transport without relying on colour, aligned columns, or soft-wrap boundaries.
- Keep durable task state current with `terminal-kit agent checkpoint`: use `working`, `needs-attention`, `review`, and `done` as the work advances. Include concise proof and the next executable action when useful. This state is for agents and automation; the operator does not maintain it.
- Preserve user work and stay inside the terminal-kit task checkout. Stop for the approval-required consequence classes in the terminal-kit machine policy.
- Finish with a concise result, exact checks/evidence, and any useful continuation. A fresh agent should be able to continue from the receipt and repository without the chat transcript.
BOOTSTRAP

if (( $# == 0 )); then
  set -- "$AGENT_BOOTSTRAP"
else
  set -- "$@" "$AGENT_BOOTSTRAP"
fi

exec /bin/bash "$WORK" "$@"
