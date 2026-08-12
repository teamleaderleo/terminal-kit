#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/config/zsh/terminal.zsh"
fi

if command -v tmux >/dev/null 2>&1; then
  check_socket="terminal-kit-check-$$"
  tmux -L "$check_socket" -f /dev/null new-session -d -s terminal-kit-check
  if ! tmux -L "$check_socket" source-file "$ROOT/config/tmux/tmux.conf"; then
    tmux -L "$check_socket" kill-server >/dev/null 2>&1 || true
    die "tmux rejected the managed settings"
  fi
  tmux -L "$check_socket" kill-server >/dev/null 2>&1 || true

  if tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
    log "reloaded tmux without closing sessions"
  fi
fi

# The cmux renderer cache is global across workspaces and surfaces. The original
# balanced preset kept only six renderers warm, which is small enough that a
# normal multi-project sidebar can evict an older terminal after 15 seconds and
# force a renderer rebuild on the next click. Migrate that original untouched
# default once to the existing normal preset (12 warm / 30 seconds). Explicit
# lean/ultra/automatic choices remain untouched.
nav_cache_marker="$HOME/.config/terminal-kit/navigation-cache-v1"
memory_state="$HOME/.config/terminal-kit/memory-mode"
auto_state="$HOME/.config/terminal-kit/memory-auto"
cmux_config="$HOME/.config/cmux/cmux.json"
if command -v jq >/dev/null 2>&1 \
  && [[ -r "$cmux_config" && -r "$memory_state" && ! -e "$nav_cache_marker" ]]; then
  memory_mode="$(tr -d '[:space:]' < "$memory_state")"
  automatic_mode="off"
  [[ -r "$auto_state" ]] && automatic_mode="$(tr -d '[:space:]' < "$auto_state")"
  if [[ "$memory_mode" == balanced && "$automatic_mode" != on ]]; then
    temporary="$(mktemp -t terminal-kit-navigation-cache)"
    jq '
      .terminal.rendererRealization = {
        enabled: true,
        idleSeconds: 30,
        maxWarmRenderers: 12
      }
      | .terminal.agentHibernation = {
          enabled: false,
          idleSeconds: 5,
          maxLiveTerminals: 12
        }
    ' "$cmux_config" > "$temporary"
    jq empty "$temporary"
    mv "$temporary" "$cmux_config"
    printf 'normal\n' > "$memory_state"
    mkdir -p "$(dirname "$nav_cache_marker")"
    : > "$nav_cache_marker"
    log "kept 12 recent terminal renderers warm for smoother navigation"
  else
    mkdir -p "$(dirname "$nav_cache_marker")"
    : > "$nav_cache_marker"
  fi
fi

if command -v cmux >/dev/null 2>&1 && cmux ping >/dev/null 2>&1; then
  cmux reload-config >/dev/null 2>&1 || cmux config reload >/dev/null 2>&1 || true
  if cmux config doctor >/dev/null 2>&1; then
    log "reloaded cmux"
  else
    warn "cmux reloaded, but its config doctor reported a problem"
  fi
fi

# Karabiner watches its config directory and reloads automatically after a file
# update. Merge only portable mappings plus terminal-kit's owned rule; leave
# device-specific and unrelated local profile state alone. Fresh test homes omit
# both Karabiner and Homebrew jq, so skip this optional layer in that case.
if command -v jq >/dev/null 2>&1 || [[ -e "$HOME/.config/karabiner/karabiner.json" ]]; then
  /bin/bash "$ROOT/scripts/karabiner.sh" apply --quiet
fi

# Ctrl-Tab is the direct cmux binding. Cmd-Tab is a macOS alias implemented by
# Karabiner because the OS normally owns Cmd-Tab before cmux can see it. Verify
# both halves after every apply so a broken alias is visible immediately while
# the direct portable binding remains usable.
if command -v jq >/dev/null 2>&1 && [[ -r "$cmux_config" ]]; then
  next_binding="$(jq -r '.shortcuts.bindings.nextSurface // empty' "$cmux_config")"
  prev_binding="$(jq -r '.shortcuts.bindings.prevSurface // empty' "$cmux_config")"
  if [[ "$next_binding" != 'ctrl+tab' || "$prev_binding" != 'ctrl+shift+tab' ]]; then
    warn "cmux tab navigation bindings drifted; expected Ctrl-Tab / Ctrl-Shift-Tab"
  fi
fi

karabiner_live="$HOME/.config/karabiner/karabiner.json"
if command -v jq >/dev/null 2>&1 && [[ -r "$karabiner_live" ]]; then
  if jq -e '
    any((.profiles // [])[]?.complex_modifications.rules[]?;
      (.description // "") == "terminal-kit: browser-style cmux surface switching"
      and any((.manipulators // [])[]?;
        .from.key_code == "tab"
        and ((.from.modifiers.mandatory // []) | index("command")) != null
        and .to[0].key_code == "tab"
        and ((.to[0].modifiers // []) | index("left_control")) != null
      )
    )
  ' "$karabiner_live" >/dev/null; then
    :
  else
    warn "Cmd-Tab alias is missing from Karabiner; Ctrl-Tab still works directly"
  fi
elif [[ -d "/Applications/Karabiner-Elements.app" ]]; then
  warn "Karabiner is installed but has no readable config; Cmd-Tab alias may be unavailable"
fi

if [[ "$(uname -s)" == "Darwin" ]] && pgrep -x Ghostty >/dev/null 2>&1; then
  if osascript >/dev/null 2>&1 <<'APPLESCRIPT'
tell application "Ghostty"
  if (count of terminals) > 0 then
    perform action "reload_config" on item 1 of terminals
  end if
end tell
APPLESCRIPT
  then
    log "reloaded Ghostty"
  else
    warn "Ghostty is still open; press Command-Shift-, to reload"
  fi
fi

log "settings applied"
