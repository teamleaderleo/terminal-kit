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
