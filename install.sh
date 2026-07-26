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

chmod +x "$ROOT/install.sh" "$ROOT/bin/terminal-kit" "$ROOT/scripts/"*.sh

BACKUP_DIR="$HOME/.config/terminal-kit-backups/$(date +%Y%m%d-%H%M%S)"
export BACKUP_DIR
mkdir -p "$BACKUP_DIR"

if [[ "$install_tools" == true ]]; then
  "$ROOT/scripts/install-tools.sh"
fi

# Ghostty and cmux both read this path. Load behaviour first, then appearance,
# so the visual layer can override the older base colours cleanly.
ghostty_behaviour_include="config-file = \"$ROOT/config/ghostty/config\""
ghostty_appearance_include="config-file = \"$ROOT/config/ghostty/appearance\""
replace_managed_block "$HOME/.config/ghostty/config" "ghostty" <<EOF_GHOSTTY
$ghostty_behaviour_include
$ghostty_appearance_include
EOF_GHOSTTY

replace_managed_block "$HOME/Library/Application Support/com.mitchellh.ghostty/config" "ghostty" <<EOF_GHOSTTY_MAC
$ghostty_behaviour_include
$ghostty_appearance_include
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

# cmux has no include mechanism, so this repo owns its UI preferences. Preserve
# the previous file in the timestamped backup before replacing changed content.
cmux_source="$ROOT/config/cmux/cmux.json.example"
cmux_target="$HOME/.config/cmux/cmux.json"
mkdir -p "$(dirname "$cmux_target")"
if [[ ! -e "$cmux_target" ]] || ! cmp -s "$cmux_source" "$cmux_target"; then
  if [[ -e "$cmux_target" ]]; then
    backup_file "$cmux_target"
  fi
  cp "$cmux_source" "$cmux_target"
  log "synced cmux settings"
fi

"$ROOT/scripts/apply.sh"

log "installed from $ROOT"
log "backups: $BACKUP_DIR"
log "open one fresh shell, then use 'tk' for future updates"
