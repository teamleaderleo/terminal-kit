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
- Own a meaningful outcome and continue through covered executable steps. Ordinary reversible repository work may proceed through implementation, checks, self-review, commits, and operator-controlled integration when repository policy and permissions allow.
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
