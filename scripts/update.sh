#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

check_only=false
case "${1:-}" in
  --check) check_only=true ;;
  '') ;;
  -h|--help|help)
    printf 'Usage: terminal-kit update [--check]\n\n'
    printf 'Fetch, show incoming commits, fast-forward, and reinstall.\n'
    printf -- '--check only fetches and shows what would change.\n'
    exit 0
    ;;
  *) die "unknown option: $1" ;;
esac

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a Git checkout"
upstream="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
  || die "the current branch has no upstream; check out main"

git -C "$ROOT" fetch --quiet
incoming="$(git -C "$ROOT" rev-list --count "HEAD..$upstream")"
if [[ "$incoming" == 0 ]]; then
  log "up to date with $upstream"
  exit 0
fi

git -C "$ROOT" --no-pager log --oneline --no-decorate "HEAD..$upstream"
git -C "$ROOT" --no-pager diff --stat "HEAD...$upstream" | tail -n 1
if [[ "$check_only" == true ]]; then
  log "$incoming new commit(s); run tk update to install them"
  exit 0
fi

git -C "$ROOT" pull --ff-only --quiet
/bin/bash "$ROOT/install.sh" --skip-tools
