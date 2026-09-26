# `tk` is terminal-kit. After update or install, reload this shell yourself;
# nothing replaces the running shell behind your back.
tk() {
  command terminal-kit "$@" || return
  case "${1:-}" in
    install|update)
      [[ "${2:-}" == --check ]] || print -r -- 'terminal-kit: run exec zsh to load the new shell config'
      ;;
  esac
}
