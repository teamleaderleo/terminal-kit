# terminal-kit

A small public MIT-licensed macOS dotfiles repo for Ghostty, cmux, tmux, and Zsh.

The Git checkout stays in `~/Projects/terminal-kit`. The installer adds tiny managed include blocks to your existing shell, tmux, and Ghostty files. cmux does not support config includes, so the repo owns `~/.config/cmux/cmux.json` and backs up the previous copy before replacing changed settings.

## Install

```sh
git clone https://github.com/teamleaderleo/terminal-kit.git ~/Projects/terminal-kit \
  && ~/Projects/terminal-kit/install.sh
```

Open one fresh shell. Future updates use one command:

```sh
tk
```

## Commands

```text
terminal-kit update       Pull Git changes and reload everything
tk                        Same update, then refresh the current Zsh
terminal-kit apply        Apply local files without pulling Git
terminal-kit tools        Install missing Homebrew tools
terminal-kit doctor       Check files, commands, and syntax
terminal-kit test         Run the repo tests
terminal-kit publish      Create or push the public GitHub repo
terminal-kit edit         Open the repo in Finder or $EDITOR
terminal-kit uninstall    Remove the managed include blocks
```

## Managed files

| Repo file | Loaded by |
| --- | --- |
| `config/ghostty/config` | Ghostty and cmux behaviour and keybindings |
| `config/ghostty/appearance` | Ghostty and cmux colours and typography |
| `config/tmux/tmux.conf` | `~/.tmux.conf` |
| `config/zsh/terminal.zsh` | `~/.zshrc` |
| `config/cmux/cmux.json.example` | Synced to `~/.config/cmux/cmux.json` |

Backups go to `~/.config/terminal-kit-backups/`.

## Native-style command editing

The editable Zsh command line uses macOS-style selection and clipboard behaviour:

```text
Cmd+A                 Select the whole command
Shift+Left/Right      Select characters
Option+Shift+Arrow    Select words
Cmd+Shift+Left/Right  Select to the beginning/end
Cmd+C                 Copy the command-line selection
Cmd+X                 Cut the command-line selection
Cmd+V                 Paste; replaces a command-line selection
Backspace/Delete      Delete the command-line selection
Cmd+Backspace         Delete to the beginning of the line
Cmd+Delete            Delete to the end of the line
Option+Backspace      Delete the previous word
Cmd+Z                 Undo
Cmd+Shift+Z           Redo
Ctrl+C                Interrupt the running command
```

Clicking within an active prompt moves the command cursor. Dragging terminal output copies it automatically; `Cmd+Shift+C` is the explicit screen-selection copy shortcut.

## Session behaviour

`tk` uses `tmux source-file`, leaving the tmux server, sessions, panes, and running programs open. It asks cmux and Ghostty to reload their settings. The current Zsh refreshes its bindings. Other open shells pick them up after `source ~/.zshrc` or the next fresh shell.

## Public-repo safety

Keep machine credentials and private values outside this repo. Avoid committing tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history. Put machine-specific private additions in your existing local config files outside the managed include blocks.

## Deep indigo appearance

The terminal uses GitHub Dark Default as its ANSI palette with a quieter indigo base:

```ini
theme = GitHub Dark Default
background = #171923
foreground = #D8DBE8
cursor-color = #93A4E8
```

The cmux sidebar uses a matching dark indigo tint. The beta TextBox stays hidden by default because its rounded pill and placeholder are currently app-owned styling.

Edit the managed files, commit, push, and run `tk` on each Mac.
