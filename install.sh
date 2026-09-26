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

# The command link exists after a successful install. Capture this before the
# installer repairs it so first-run guidance stays limited to the first run.
first_install=true
if [[ -e "$HOME/.local/bin/terminal-kit" || -L "$HOME/.local/bin/terminal-kit" ]]; then
  first_install=false
fi

# Only the two public entry points need executable bits. Helper scripts are run
# explicitly through Bash so installation never changes tracked file modes.
chmod +x "$ROOT/install.sh" "$ROOT/bin/terminal-kit"

BACKUP_DIR="$HOME/.config/terminal-kit-backups/$(date +%Y%m%d-%H%M%S)"
export BACKUP_DIR
mkdir -p "$BACKUP_DIR"

if [[ "$install_tools" == true ]]; then
  /bin/bash "$ROOT/scripts/install-tools.sh"
fi

# Machine-local settings (tk set) live in ~/.config/terminal-kit/settings.json.
# Render them into cmux.json and the Ghostty glass include; files are only
# replaced (with a backup) when their content changes.
python3 "$ROOT/scripts/settings.py" _render
glass_target="$HOME/.config/terminal-kit/glass.ghostty"

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

# GitHub Git transport is machine-local. SSH is the terminal-kit default so a
# pasted https://github.com/... clone or remote still uses the configured SSH key.
git_protocol_target="$HOME/.config/terminal-kit/git-protocol"
if [[ ! -e "$git_protocol_target" ]]; then
  printf 'ssh\n' >"$git_protocol_target"
fi
git_protocol="$(tr -d '[:space:]' <"$git_protocol_target")"
case "$git_protocol" in
  ssh|https) ;;
  *)
    warn "invalid GitHub protocol; resetting to ssh"
    git_protocol=ssh
    printf 'ssh\n' >"$git_protocol_target"
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

# Temporary activation snippets under /tmp cannot survive a reboot and should
# never become permanent shell startup dependencies. Remove only the narrow
# source/dot-command form before repairing terminal-kit's own managed block.
prune_ephemeral_zsh_sources "$HOME/.zshrc"
replace_managed_block "$HOME/.zshrc" "zsh" <<EOF_ZSH
if [[ -r "$ROOT/config/zsh/init.zsh" ]]; then
  source "$ROOT/config/zsh/init.zsh"
fi
EOF_ZSH

remove_retired_state

mkdir -p "$HOME/.local/bin"
ln -sfn "$ROOT/bin/terminal-kit" "$HOME/.local/bin/terminal-kit"

# Keep GitHub CLI cloning and raw Git HTTPS URLs on the same saved transport.
/bin/bash "$ROOT/scripts/git.sh" apply >/dev/null

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
if [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
  log "backup: $display_backup"
else
  rmdir "$BACKUP_DIR"
fi
if [[ "$first_install" == true ]]; then
  log "open a fresh shell once after first install"
fi
