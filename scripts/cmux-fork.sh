#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

CMUX_REPO="${TERMINAL_KIT_CMUX_REPO:-https://github.com/teamleaderleo/cmux.git}"
CMUX_DIR="${TERMINAL_KIT_CMUX_DIR:-$HOME/Projects/cmux-terminal-kit}"
CMUX_TAG="${TERMINAL_KIT_CMUX_TAG:-terminal-kit}"

# terminal-kit normally prefers SSH for GitHub, including a global HTTPS-to-SSH
# rewrite. The cmux dogfood checkout is a public, read-only fetch path, and some
# networks block GitHub SSH on port 22. Ignore only the global Git config for
# these network operations so this helper stays on HTTPS without changing the
# user's normal Git transport preference.
git_https() {
  GIT_CONFIG_GLOBAL=/dev/null git "$@"
}

usage() {
  cat <<'HELP'
Usage: terminal-kit cmux <command>

  status   Show the fork checkout, revision, and Ghostty pin
  sync     Clone or fast-forward the fork and sync its submodules
  setup    Sync the fork and run cmux's normal developer setup
  build    Setup, then build the isolated terminal-kit tagged app
  launch   Setup, build, and launch the isolated terminal-kit tagged app
  path     Print the local cmux fork checkout path

Environment overrides:
  TERMINAL_KIT_CMUX_REPO   Fork Git URL
  TERMINAL_KIT_CMUX_DIR    Checkout directory
  TERMINAL_KIT_CMUX_TAG    Isolated cmux dev-build tag
HELP
}

ensure_checkout() {
  if [[ -d "$CMUX_DIR/.git" ]]; then
    return
  fi
  if [[ -e "$CMUX_DIR" ]]; then
    die "cmux fork path exists but is not a Git checkout: $CMUX_DIR"
  fi

  mkdir -p "$(dirname "$CMUX_DIR")"
  log "cloning cmux fork into ${CMUX_DIR/#$HOME/\~} over HTTPS"
  git_https clone "$CMUX_REPO" "$CMUX_DIR"
}

sync_checkout() {
  ensure_checkout

  local branch
  branch="$(git -C "$CMUX_DIR" branch --show-current 2>/dev/null || true)"
  [[ "$branch" == main ]] || die "cmux fork checkout must be on main; found ${branch:-detached}"

  local dirty
  dirty="$(git -C "$CMUX_DIR" status --short)"
  [[ -z "$dirty" ]] || die "cmux fork checkout has local changes; commit or stash them before sync"

  # A previous run may have stored an SSH origin. Keep this one checkout on the
  # explicit fork URL; the scoped Git environment below prevents the user's
  # global HTTPS-to-SSH rewrite from changing the transport during fetches.
  git -C "$CMUX_DIR" remote set-url origin "$CMUX_REPO"
  git_https -C "$CMUX_DIR" pull --ff-only
  git_https -C "$CMUX_DIR" submodule sync --recursive
  git_https -C "$CMUX_DIR" submodule update --init --recursive
}

setup_checkout() {
  sync_checkout
  (
    cd "$CMUX_DIR"
    # setup.sh performs another recursive submodule update. Propagate the same
    # scoped HTTPS behavior so it cannot fall back to the global SSH rewrite.
    GIT_CONFIG_GLOBAL=/dev/null ./scripts/setup.sh
  )
}

print_status() {
  printf 'terminal-kit cmux fork\n'
  printf 'repo:     %s\n' "$CMUX_REPO"
  printf 'path:     %s\n' "${CMUX_DIR/#$HOME/\~}"
  printf 'tag:      %s\n' "$CMUX_TAG"

  if [[ ! -d "$CMUX_DIR/.git" ]]; then
    printf 'checkout: missing\n'
    return
  fi

  printf 'branch:   %s\n' "$(git -C "$CMUX_DIR" branch --show-current 2>/dev/null || printf detached)"
  printf 'commit:   %s\n' "$(git -C "$CMUX_DIR" rev-parse --short HEAD)"
  printf 'tree:     %s\n' "$([[ -z "$(git -C "$CMUX_DIR" status --short)" ]] && printf clean || printf dirty)"
  if git -C "$CMUX_DIR" rev-parse HEAD:ghostty >/dev/null 2>&1; then
    printf 'ghostty:  %s\n' "$(git -C "$CMUX_DIR" rev-parse --short HEAD:ghostty)"
  fi
}

command_name="${1:-status}"
shift || true

case "$command_name" in
  status)
    print_status
    ;;
  sync|update)
    sync_checkout
    print_status
    ;;
  setup)
    setup_checkout
    ;;
  build)
    setup_checkout
    (
      cd "$CMUX_DIR"
      ./scripts/reload.sh --tag "$CMUX_TAG"
    )
    ;;
  launch|dev)
    setup_checkout
    (
      cd "$CMUX_DIR"
      ./scripts/reload.sh --tag "$CMUX_TAG" --launch
    )
    ;;
  path)
    printf '%s\n' "$CMUX_DIR"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
