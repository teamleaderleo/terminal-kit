# Preview updates in the current shell. Applying an inspected revision or running
# install replaces this shell so prompt and ZLE changes load once from startup.
terminal-update() {
  local _terminal_kit_command="${1:-update}" _terminal_kit_update_action="${2:-}"
  if (( $# == 0 )); then
    set -- update
  fi

  command terminal-kit "$@" || return
  case "$_terminal_kit_command" in
    install)
      exec zsh
      ;;
    update)
      if [[ "$_terminal_kit_update_action" == --apply ]]; then
        exec zsh
      fi
      ;;
  esac
}
alias tk='terminal-update'
