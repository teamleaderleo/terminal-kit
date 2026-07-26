# Agent notes

This repo manages macOS terminal settings for Ghostty, cmux, tmux, and Zsh.

## User preferences

- Keep the default appearance simple: deep blue background and white text.
- Preserve Command-C and Command-V for the macOS clipboard.
- Preserve Control-C for process interruption.
- Prefer one-command updates through `tk`.
- Keep running tmux sessions and terminal processes alive during updates.

## Editing rules

- Keep user-facing settings in `config/`.
- Preserve the include-based installer; avoid replacing the user's complete `.zshrc`, `.tmux.conf`, or Ghostty host files.
- Keep installer runs repeatable.
- Back up host files before changing managed blocks.
- Avoid sending commands into existing tmux panes.
- Keep cmux TextBox focus disabled by default so terminal signals remain direct.

## Checks

Run before committing:

```sh
./scripts/test.sh
```

On macOS with the tools installed, also run:

```sh
terminal-kit doctor
terminal-kit apply
```
