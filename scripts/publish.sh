#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
repo_name="${1:-terminal-kit}"
visibility="${TERMINAL_KIT_VISIBILITY:-public}"

command -v gh >/dev/null 2>&1 || die "GitHub CLI is missing; install it with: brew install gh"
gh auth status >/dev/null 2>&1 || die "sign in first with: gh auth login"
[[ "$visibility" == "public" || "$visibility" == "private" ]] || die "TERMINAL_KIT_VISIBILITY must be public or private"

cd "$ROOT"
if [[ ! -d .git ]]; then
  git init -b main
fi

git add .
if ! git diff --cached --quiet; then
  git commit -m "Add terminal settings"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin HEAD
  log "pushed updates to $(git remote get-url origin)"
else
  gh repo create "$repo_name" "--$visibility" --source=. --remote=origin --push
  log "created and pushed $visibility GitHub repo: $repo_name"
fi
