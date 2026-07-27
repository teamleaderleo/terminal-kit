#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/lib.sh"

[[ "$(uname -s)" == "Darwin" ]] || die "this kit currently targets macOS"

install_tools=true
for arg in "$@"; do
  case "$arg" in
    --skip-tools) install_tools=false ;;
    *) die "unknown option: $arg" ;;
  esac
done

# Only the two public entry points need executable bits. Helper scripts are run
# explicitly through Bash so installation never changes tracked file modes.
chmod +x "$ROOT/install.sh" "$ROOT/bin/terminal-kit"

BACKUP_DIR="$HOME/.config/terminal-kit-backups/$(date +%Y%m%d-%H%M%S)"
export BACKUP_DIR
mkdir -p "$BACKUP_DIR"

if [[ "$install_tools" == true ]]; then
  /bin/bash "$ROOT/scripts/install-tools.sh"
fi

# Keep changeable glass state outside Git so switching presets never dirties the
# checkout or blocks a later `tk` pull.
glass_target="$HOME/.config/terminal-kit/glass.ghostty"
mkdir -p "$(dirname "$glass_target")"
if [[ ! -e "$glass_target" ]]; then
  cat >"$glass_target" <<'EOF_GLASS'
# terminal-kit glass preset: regular
# Local machine state; intentionally kept outside the Git repository.
background-opacity = 0.90
background-blur = macos-glass-regular
background-opacity-cells = false
EOF_GLASS
fi

# Scroll speed is machine-local for the same reason: Mos settings, mice, and
# trackpads vary, and choosing a preset should never create a Git conflict.
scroll_target="$HOME/.config/terminal-kit/scroll-speed"
if [[ ! -e "$scroll_target" ]]; then
  printf '1.4\n' >"$scroll_target"
fi
scroll_speed="$(tr -d '[:space:]' <"$scroll_target")"
if ! [[ "$scroll_speed" =~ ^[0-9]+([.][0-9]+)?$ ]] \
  || ! awk -v speed="$scroll_speed" 'BEGIN { exit !(speed >= 0.25 && speed <= 4) }'; then
  warn "invalid saved scroll speed; resetting to 1.4"
  scroll_speed=1.4
  printf '1.4\n' >"$scroll_target"
fi

# The calm prompt is the default. Preserve explicit detailed/off choices and
# migrate the older generic "on" value to minimal.
prompt_target="$HOME/.config/terminal-kit/prompt"
if [[ ! -e "$prompt_target" ]]; then
  printf 'minimal\n' >"$prompt_target"
else
  prompt_mode="$(tr -d '[:space:]' <"$prompt_target")"
  case "$prompt_mode" in
    on|enable)
      printf 'minimal\n' >"$prompt_target"
      ;;
    minimal|detailed|off)
      ;;
    *)
      warn "invalid prompt mode; resetting to minimal"
      printf 'minimal\n' >"$prompt_target"
      ;;
  esac
fi

# Automatic sidebar status hints arrived after the workspace row was first drawn,
# which made row heights jump. Migrate the original experiment to off once, then
# preserve any later explicit `tk hints on` choice through the version marker.
hints_target="$HOME/.config/terminal-kit/hints"
hints_layout_marker="$HOME/.config/terminal-kit/hints-layout-v2"
if [[ ! -e "$hints_layout_marker" ]]; then
  printf 'off\n' >"$hints_target"
  : >"$hints_layout_marker"
elif [[ ! -e "$hints_target" ]]; then
  printf 'off\n' >"$hints_target"
fi

# cmux's built-in text editor wraps by default. Wide mode is stored locally so
# enabling horizontal scrolling survives updates without changing tracked JSON.
editor_wrap_target="$HOME/.config/terminal-kit/editor-wrap"
if [[ ! -e "$editor_wrap_target" ]]; then
  printf 'wrap\n' >"$editor_wrap_target"
fi
editor_wrap_mode="$(tr -d '[:space:]' <"$editor_wrap_target")"
case "$editor_wrap_mode" in
  wrap|wide) ;;
  *)
    warn "invalid editor mode; resetting to wrap"
    editor_wrap_mode=wrap
    printf 'wrap\n' >"$editor_wrap_target"
    ;;
esac

# Ghostty and cmux both read this path. Load behaviour, shared appearance, then
# the machine-local glass preset so theme and glass rotation remain independent.
ghostty_behaviour_include="config-file = \"$ROOT/config/ghostty/config\""
ghostty_appearance_include="config-file = \"$ROOT/config/ghostty/appearance\""
ghostty_glass_include="config-file = \"$glass_target\""
replace_managed_block "$HOME/.config/ghostty/config" "ghostty" <<EOF_GHOSTTY
$ghostty_behaviour_include
$ghostty_appearance_include
$ghostty_glass_include
EOF_GHOSTTY

replace_managed_block "$HOME/Library/Application Support/com.mitchellh.ghostty/config" "ghostty" <<EOF_GHOSTTY_MAC
$ghostty_behaviour_include
$ghostty_appearance_include
$ghostty_glass_include
EOF_GHOSTTY_MAC

replace_managed_block "$HOME/.tmux.conf" "tmux" <<EOF_TMUX
source-file "$ROOT/config/tmux/tmux.conf"
EOF_TMUX

# .zshenv runs before .zshrc, so standard macOS tools remain available to NVM,
# Bun, completion scripts, and the rest of the user's existing startup file.
replace_managed_block "$HOME/.zshenv" "environment" <<EOF_ZSHENV
if [[ -r "$ROOT/config/zsh/env.zsh" ]]; then
  source "$ROOT/config/zsh/env.zsh"
fi
EOF_ZSHENV

replace_managed_block "$HOME/.zshrc" "zsh" <<EOF_ZSH
if [[ -r "$ROOT/config/zsh/init.zsh" ]]; then
  source "$ROOT/config/zsh/init.zsh"
fi
EOF_ZSH

mkdir -p "$HOME/.local/bin"
ln -sfn "$ROOT/bin/terminal-kit" "$HOME/.local/bin/terminal-kit"

# cmux has no include mechanism, so render its managed config with machine-local
# scroll and editor preferences before comparing or installing it.
cmux_source="$ROOT/config/cmux/cmux.json.example"
cmux_target="$HOME/.config/cmux/cmux.json"
cmux_rendered="$(mktemp -t terminal-kit-cmux)"
cp "$cmux_source" "$cmux_rendered"
if [[ "$scroll_speed" != "1.4" ]]; then
  /usr/bin/plutil -replace terminal.scrollSpeed -float "$scroll_speed" "$cmux_rendered"
fi
if [[ "$editor_wrap_mode" == "wide" ]]; then
  /usr/bin/plutil -replace fileEditor.wordWrap -bool false "$cmux_rendered"
fi
mkdir -p "$(dirname "$cmux_target")"
if [[ ! -e "$cmux_target" ]] || ! cmp -s "$cmux_rendered" "$cmux_target"; then
  if [[ -e "$cmux_target" ]]; then
    backup_file "$cmux_target"
  fi
  cp "$cmux_rendered" "$cmux_target"
  log "synced cmux settings"
fi
rm -f "$cmux_rendered"

# The personal Dock is deliberately generic. Project-local .cmux/dock.json files
# can replace it with repo-specific logs, tests, servers, and Git controls.
dock_source="$ROOT/config/cmux/dock.json.example"
dock_target="$HOME/.config/cmux/dock.json"
if [[ ! -e "$dock_target" ]] || ! cmp -s "$dock_source" "$dock_target"; then
  if [[ -e "$dock_target" ]]; then
    backup_file "$dock_target"
  fi
  cp "$dock_source" "$dock_target"
  log "synced cmux Dock controls"
fi

/bin/bash "$ROOT/scripts/apply.sh"

display_root="${ROOT/#$HOME/\~}"
display_backup="${BACKUP_DIR/#$HOME/\~}"
log "installed from $display_root"
log "backup: $display_backup"
log "open a fresh shell once after first install"
