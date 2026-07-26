# terminal-kit

A small public MIT-licensed macOS dotfiles repo for Ghostty, cmux, tmux, and Zsh.

The Git checkout stays in `~/Projects/terminal-kit`. The installer adds small managed include blocks to your existing shell, tmux, and Ghostty files. cmux does not support config includes, so the repo owns `~/.config/cmux/cmux.json` and `~/.config/cmux/dock.json`, backing up previous copies before replacing changed settings.

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
terminal-kit theme        Browse, test, set, rotate, or automate cmux themes
terminal-kit glass        Switch native macOS glass presets
terminal-kit scroll       Tune cmux wheel and trackpad scroll speed
terminal-kit prompt       Enable or disable the contextual prompt
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
terminal-kit theme test             Render a repeatable readability screen
terminal-kit theme set "Vesper"     Select a theme
terminal-kit theme next             Cycle through the top group
terminal-kit theme random           Pick a random top-group theme
terminal-kit theme daily            Apply today's deterministic theme
terminal-kit theme auto on          Enable low-frequency daily rotation
terminal-kit theme auto off         Disable automatic rotation
```

The automatic mode uses a small launchd agent. It checks every six hours and only changes the theme when the daily choice differs, which also handles laptop sleep and login without keeping a process running.

## Native glass controls

Glass state lives in `~/.config/terminal-kit/glass.ghostty`, outside Git, so changing it never makes the repository dirty.

```text
terminal-kit glass current      Show the current preset
terminal-kit glass regular      Native regular glass, balanced for reading
terminal-kit glass clear        Native clear Liquid Glass
terminal-kit glass immersive    Clear glass through full-screen terminal app cells
terminal-kit glass opaque       Disable transparency and blur
terminal-kit glass cycle        Rotate through the four presets
```

The default is regular native glass at 90% opacity. `Cmd+Shift+O` remains a quick temporary opacity toggle. A complete cmux restart may be required when changing the underlying macOS material.

## Scroll controls

Scroll speed lives in `~/.config/terminal-kit/scroll-speed`, outside Git. cmux applies this multiplier to mouse-wheel and trackpad deltas; Mos can continue providing the smoothing and inertia curve.

```text
terminal-kit scroll current     Show the saved and active multiplier
terminal-kit scroll precise     0.9x for close reading
terminal-kit scroll balanced    1.0x cmux default
terminal-kit scroll brisk       1.4x terminal-kit default
terminal-kit scroll fast        1.8x for long logs
terminal-kit scroll set 1.55    Set a custom value
terminal-kit scroll cycle       Rotate through the four presets
```

Use cmux's multiplier as the main speed control rather than stacking it immediately with Ghostty's mouse-scroll multiplier. A Mos per-app profile can then adjust gain and duration for cmux without making Apple Terminal or browsers too fast.

## Contextual prompt

The compact Starship prompt is enabled by default and uses ordinary ANSI colours so it follows the active terminal theme. It shows the current path, Git branch and state, command duration, background jobs, and failures without Powerline blocks or Nerd Font dependencies.

```text
terminal-kit prompt status
terminal-kit prompt on
terminal-kit prompt off
exec zsh                       Apply a prompt-state change
```

## Modern terminal tools

The kit installs a restrained terminal-native toolbelt:

- `y` opens Yazi and changes the shell directory to the folder selected on exit.
- `lg` opens Lazygit in the current repository.
- `bt` opens btop.
- `rg`, `fd`, and `jq` provide fast content search, file search, and JSON processing.

Yazi image previews can pass through tmux into Ghostty-compatible terminals. In cmux, `Cmd+Up` and `Cmd+Down` jump between shell prompts instead of scrolling line-by-line through command output.

cmux's Command Palette includes Yazi, Lazygit, btop, themes, glass, scrolling, and readability testing. The global Dock provides System and Feed panels; a project-local `.cmux/dock.json` can replace it with repo-specific logs, tests, servers, or Git controls.

## Managed files

| Repo file | Loaded by |
| --- | --- |
| `config/ghostty/config` | Ghostty and cmux behaviour and keybindings |
| `config/ghostty/appearance` | Ghostty and cmux theme fallback and typography |
| `~/.config/terminal-kit/glass.ghostty` | Machine-local native glass preset |
| `~/.config/terminal-kit/scroll-speed` | Machine-local cmux scroll multiplier |
| `~/.config/terminal-kit/prompt` | Machine-local prompt switch |
| `config/cmux/cmux.json.example` | Rendered to `~/.config/cmux/cmux.json` with local scroll speed |
| `config/cmux/dock.json.example` | Synced to `~/.config/cmux/dock.json` |
| `config/starship/terminal-kit.toml` | Compact contextual prompt |
| `config/tmux/tmux.conf` | `~/.tmux.conf` |
| `config/zsh/env.zsh` | `~/.zshenv`; restores standard macOS and Homebrew command paths early |
| `config/zsh/init.zsh` | Per-shell helper, prompt, and plugin bootstrap |
| `config/zsh/terminal.zsh` | Editing widgets, history, and aliases |
| `config/zsh/tools.zsh` | Yazi and modern-tool wrappers |
| `config/zsh/highlight.zsh` | Subdued sage, salmon, and indigo syntax colours |

Backups go to `~/.config/terminal-kit-backups/`.

## Appearance

Catppuccin Mocha is the fallback theme, while cmux's managed theme override controls the complete active palette:

```ini
theme = Catppuccin Mocha
font-family = Menlo
font-size = 13
font-thicken = true
sidebar-font-size = 14
surface-tab-bar-font-size = 11
```

The slightly larger, gently thickened text is intended to improve character separation and distance legibility. Balanced padding keeps the grid centred while panes resize.

The base configuration does not fix its own background, foreground, cursor, or selection hex values, so Rosé Pine, Vesper, Catppuccin, and other selected themes can display their full palettes. The cmux sidebar and tmux use theme-responsive backgrounds and ANSI colours. `bat` uses its `base16` theme and Delta follows `BAT_THEME` where possible.

The built-in Markdown viewer uses a 16-point body size and a narrower reading column, and the plain-text editor wraps long lines.

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

The beta cmux TextBox stays hidden for new terminals. Zsh remains the command editor, with Starship only rendering the contextual prompt around it.

## Ricing roadmap

`docs/ricing-roadmap.md` records the broader cmux customisation surface: custom actions, project layouts, Dock controls, browser automation, notifications, workspace metadata, remaining theme gaps, and sensible future upgrades.

## Session behaviour

`tk` reloads the live tmux server without closing sessions, panes, or running programs. It asks cmux and Ghostty to reload their settings. Other open shells pick up shell changes after `exec zsh`, `source ~/.zshrc`, or opening a fresh workspace.

## Public-repo safety

Keep machine credentials and private values outside this repo. Avoid committing tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history. Put machine-specific private additions in your existing local config files outside the managed include blocks.
