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

# Ghostty and cmux both read this path. Ghostty may also load its macOS path
# afterwards, so the same managed include is placed there as well.
ghostty_include="config-file = \"$ROOT/config/ghostty/config\""
replace_managed_block "$HOME/.config/ghostty/config" "ghostty" <<EOF_GHOSTTY
$ghostty_include
EOF_GHOSTTY

replace_managed_block "$HOME/Library/Application Support/com.mitchellh.ghostty/config" "ghostty" <<EOF_GHOSTTY_MAC
$ghostty_include
EOF_GHOSTTY_MAC

replace_managed_block "$HOME/.tmux.conf" "tmux" <<EOF_TMUX
source-file "$ROOT/config/tmux/tmux.conf"
EOF_TMUX

replace_managed_block "$HOME/.zshrc" "zsh" <<EOF_ZSH
export PATH="\$HOME/.local/bin:\$PATH"
if [[ -r "$ROOT/config/zsh/terminal.zsh" ]]; then
  source "$ROOT/config/zsh/terminal.zsh"
fi
EOF_ZSH

mkdir -p "$HOME/.local/bin"
ln -sfn "$ROOT/bin/terminal-kit" "$HOME/.local/bin/terminal-kit"

# Give cmux a useful starter file only when the user has no cmux file yet.
if [[ ! -e "$HOME/.config/cmux/cmux.json" ]]; then
  mkdir -p "$HOME/.config/cmux"
  cp "$ROOT/config/cmux/cmux.json.example" "$HOME/.config/cmux/cmux.json"
  log "created a cmux starter file"
fi

"$ROOT/scripts/apply.sh"

log "installed from $ROOT"
log "backups: $BACKUP_DIR"
log "open one fresh shell, then use 'tk' for future updates"
