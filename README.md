# terminal-kit

A small public MIT-licensed macOS dotfiles repo for Ghostty, cmux, tmux, and Zsh.

The Git checkout stays in `~/Projects/terminal-kit`. The installer adds small managed include blocks to your existing shell, tmux, and Ghostty files. cmux does not support config includes, so the repo owns `~/.config/cmux/cmux.json` and backs up the previous copy before replacing changed settings.

## Install

```sh
git clone https://github.com/teamleaderleo/terminal-kit.git ~/Projects/terminal-kit
~/Projects/terminal-kit/install.sh
exec zsh
```

Future updates use one command:

```sh
tk
```

## Commands

```text
terminal-kit update       Pull Git changes, install new tools, and reload everything
tk                        Same update, then refresh the current Zsh
terminal-kit apply        Apply local files without pulling Git
terminal-kit theme        Browse, set, rotate, or automate cmux themes
terminal-kit tools        Install missing Homebrew tools
terminal-kit doctor       Check files, commands, and syntax
terminal-kit test         Run the repo tests
terminal-kit edit         Open the repository
terminal-kit uninstall    Remove the managed include blocks
```

## Theme controls

```text
terminal-kit theme                  Open cmux's interactive browser
terminal-kit theme current          Show active light and dark themes
terminal-kit theme shortlist        Show the saved ranked shortlist
terminal-kit theme set "Vesper"     Select a theme
terminal-kit theme next             Cycle through the top group
terminal-kit theme random           Pick a random top-group theme
terminal-kit theme daily            Apply today's deterministic theme
terminal-kit theme auto on          Enable low-frequency daily rotation
terminal-kit theme auto off         Disable automatic rotation
```

The automatic mode uses a small launchd agent. It checks every six hours and only changes the theme when the daily choice differs, which also handles laptop sleep and login without keeping a process running.

## Managed files

| Repo file | Loaded by |
| --- | --- |
| `config/ghostty/config` | Ghostty and cmux behaviour and keybindings |
| `config/ghostty/appearance` | Ghostty and cmux theme fallback, glass, and typography |
| `config/cmux/cmux.json.example` | Synced to `~/.config/cmux/cmux.json` |
| `config/tmux/tmux.conf` | `~/.tmux.conf` |
| `config/zsh/env.zsh` | `~/.zshenv`; restores standard macOS and Homebrew command paths early |
| `config/zsh/init.zsh` | Per-shell helper and plugin bootstrap |
| `config/zsh/terminal.zsh` | Editing widgets, history, and aliases |
| `config/zsh/highlight.zsh` | Subdued sage, salmon, and indigo syntax colours |

Backups go to `~/.config/terminal-kit-backups/`.

## Appearance

Catppuccin Mocha is the fallback theme, while cmux's managed theme override controls the complete active palette:

```ini
theme = Catppuccin Mocha
background-opacity = 0.94
background-blur = macos-glass-regular
font-family = Menlo
font-size = 12.5
```

The base configuration no longer fixes its own background, foreground, cursor, or selection hex values, so Rosé Pine, Vesper, Catppuccin, and other selected themes can display their full palettes. The cmux sidebar and tmux use theme-responsive backgrounds and ANSI colours. `bat` uses its `base16` theme and Delta follows `BAT_THEME` where possible.

On macOS 26, Ghostty uses the native regular Liquid Glass material. A complete app restart may be required after changing opacity. `Cmd+Shift+O` toggles between the configured glass background and an opaque background.

## Shell experience

The prompt supports Mac-like selection, cut, copy, paste, deletion, undo, and redo while preserving standard Unix control keys such as `Ctrl+C` for process interruption.

Valid commands use muted sage, invalid tokens use subdued salmon, and paths and options use restrained indigo-grey accents.

The kit also installs:

- `zsh-syntax-highlighting` and `zsh-autosuggestions`
- `atuin` and `fzf` for searchable history
- `zoxide` for ranked directory jumping with `z` and `zi`
- `eza`, `bat`, and `grc` for restrained colour in ordinary command output
- `delta` for syntax-aware Git diffs and logs

Completion initialisation remains owned by the user's existing shell setup; terminal-kit does not run `compinit` a second time.

The beta cmux TextBox stays hidden for new terminals. The normal Zsh prompt is the primary command editor.

## Ricing roadmap

`docs/ricing-roadmap.md` records the broader cmux customisation surface: custom actions, project layouts, Dock controls, browser automation, notifications, workspace metadata, remaining theme gaps, and sensible future upgrades.

## Session behaviour

`tk` reloads the live tmux server without closing sessions, panes, or running programs. It asks cmux and Ghostty to reload their settings. Other open shells pick up shell changes after `exec zsh`, `source ~/.zshrc`, or opening a fresh workspace.

## Public-repo safety

Keep machine credentials and private values outside this repo. Avoid committing tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history. Put machine-specific private additions in your existing local config files outside the managed include blocks.
