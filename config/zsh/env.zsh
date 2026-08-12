# terminal-kit: baseline environment loaded from ~/.zshenv.

# Keep the user's existing paths, but guarantee that macOS and Homebrew tools
# remain reachable even if another startup script accidentally replaces PATH.
typeset -gU path PATH
path=(
  "$HOME/.local/bin"
  /opt/homebrew/bin
  /opt/homebrew/sbin
  /usr/local/bin
  /usr/local/sbin
  /usr/bin
  /bin
  /usr/sbin
  /sbin
  $path
)
export PATH

# Prevent BSD sed and similar macOS tools from choking on ordinary UTF-8 text
# when no character locale has been established yet.
if [[ -z "${LC_CTYPE:-}" ]]; then
  export LC_CTYPE=UTF-8
fi

# Prefer a terminal editor with mouse support and familiar editing shortcuts.
# Respect an explicit editor choice; migrate only blank/default vi/vim/nano values.
_terminal_kit_replace_legacy_editor() {
  case "$1" in
    ''|vi|vim|nano|/usr/bin/vi|/usr/bin/vim|/usr/bin/nano) return 0 ;;
    *) return 1 ;;
  esac
}

if command -v micro >/dev/null 2>&1; then
  _terminal_kit_replace_legacy_editor "${EDITOR:-}" && export EDITOR=micro
  _terminal_kit_replace_legacy_editor "${VISUAL:-}" && export VISUAL=micro
  _terminal_kit_replace_legacy_editor "${GIT_EDITOR:-}" && export GIT_EDITOR=micro
  _terminal_kit_replace_legacy_editor "${GH_EDITOR:-}" && export GH_EDITOR=micro
  _terminal_kit_replace_legacy_editor "${SUDO_EDITOR:-}" && export SUDO_EDITOR=micro
fi

unfunction _terminal_kit_replace_legacy_editor 2>/dev/null || true
