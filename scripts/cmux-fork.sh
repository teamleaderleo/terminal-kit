#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

CMUX_REPO="${TERMINAL_KIT_CMUX_REPO:-https://github.com/teamleaderleo/cmux.git}"
CMUX_DIR="${TERMINAL_KIT_CMUX_DIR:-$HOME/Projects/cmux-terminal-kit}"
CMUX_TAG="${TERMINAL_KIT_CMUX_TAG:-terminal-kit}"
LEGACY_GITHUB_REWRITE_KEY='url.git@github.com:.insteadOf'
LEGACY_GITHUB_HTTPS_PREFIX='https://github.com/'

# Keep only this helper's explicit fork/submodule fetches on HTTPS. Do not
# blank global Git config for Xcode, SwiftPM, or the rest of the build.
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

preflight_native_toolchain() {
  [[ "$(uname -s)" == Darwin ]] || die "cmux fork builds require macOS"
  command -v xcodebuild >/dev/null 2>&1 || die "full Xcode is required to build cmux"
  command -v xcrun >/dev/null 2>&1 || die "xcrun is unavailable; install or select full Xcode"

  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  [[ "$developer_dir" == */Xcode.app/Contents/Developer ]] || die "full Xcode is not selected; run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"

  if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    die "Xcode's Metal Toolchain is missing; run: xcodebuild -downloadComponent MetalToolchain"
  fi
}

preflight_git_transport() {
  if git config --global --get-all "$LEGACY_GITHUB_REWRITE_KEY" 2>/dev/null | grep -Fxq "$LEGACY_GITHUB_HTTPS_PREFIX"; then
    die "legacy global GitHub HTTPS-to-SSH rewrite is active; update terminal-kit and run: tk git apply"
  fi
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

  git -C "$CMUX_DIR" remote set-url origin "$CMUX_REPO"
  git_https -C "$CMUX_DIR" pull --ff-only
  git_https -C "$CMUX_DIR" submodule sync --recursive
  git_https -C "$CMUX_DIR" submodule update --init --recursive
}

setup_checkout() {
  preflight_native_toolchain
  preflight_git_transport
  sync_checkout
  (
    cd "$CMUX_DIR"
    ./scripts/setup.sh
  )
}

cmux_tag_slug() {
  printf '%s' "$CMUX_TAG" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

cmux_tagged_app_path() {
  local slug products app_path
  slug="$(cmux_tag_slug)"
  [[ -n "$slug" ]] || return 1
  products="$HOME/Library/Developer/Xcode/DerivedData/cmux-${slug}/Build/Products/Debug"
  app_path="$products/cmux DEV ${slug}.app"
  [[ -d "$app_path" ]] || return 1
  printf '%s\n' "$app_path"
}

cmux_tagged_process_ids() {
  local executable_path="$1" pattern
  # The path contains spaces and may contain regexp punctuation from $HOME.
  # Escape it before anchoring pgrep to argv[0] so this cannot match production
  # cmux or another tagged dev app.
  pattern="$(printf '%s' "$executable_path" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g')"
  pgrep -f "^${pattern}([[:space:]]|$)" 2>/dev/null || true
}

foreground_tagged_cmux() {
  local app_path plist executable_name executable_path bundle_id pid
  local -a pids

  app_path="$(cmux_tagged_app_path)" || die "tagged cmux app was not found after launch"
  plist="$app_path/Contents/Info.plist"
  [[ -f "$plist" ]] || die "tagged cmux Info.plist is missing: $plist"

  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
  [[ -n "$executable_name" ]] || executable_name='cmux DEV'
  executable_path="$app_path/Contents/MacOS/$executable_name"
  [[ -x "$executable_path" ]] || die "tagged cmux executable is missing: $executable_path"

  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  [[ -n "$bundle_id" ]] || die "tagged cmux bundle identifier is missing"

  pids=()
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pids=($(cmux_tagged_process_ids "$executable_path"))
    (( ${#pids[@]} > 0 )) && break
    sleep 0.1
  done
  (( ${#pids[@]} == 1 )) || die "expected one tagged cmux process at $executable_path; found ${#pids[@]}"
  pid="${pids[0]}"

  # reload.sh launches the tagged executable directly so it gets a clean,
  # tag-specific environment. Opening the exact already-running app bundle here
  # only asks LaunchServices to foreground that instance; it does not choose a
  # similarly named production cmux window.
  /usr/bin/open "$app_path" >/dev/null 2>&1 || die "could not foreground tagged cmux app: $app_path"
  sleep 0.1
  kill -0 "$pid" 2>/dev/null || die "tagged cmux process exited while being foregrounded"

  printf '\nterminal-kit cmux dogfood\n'
  printf 'app:      %s\n' "$app_path"
  printf 'bundle:   %s\n' "$bundle_id"
  printf 'pid:      %s\n' "$pid"
  printf 'commit:   %s\n' "$(git -C "$CMUX_DIR" rev-parse --short HEAD)"
  if git -C "$CMUX_DIR" rev-parse HEAD:ghostty >/dev/null 2>&1; then
    printf 'ghostty:  %s\n' "$(git -C "$CMUX_DIR" rev-parse --short HEAD:ghostty)"
  fi
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
    foreground_tagged_cmux
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
