# terminal-kit

A small public MIT-licensed macOS dotfiles repo for Ghostty, cmux, tmux, and Zsh.

The Git checkout stays in `~/Projects/terminal-kit`. The installer adds small managed include blocks to your existing shell, tmux, and Ghostty files. cmux does not support config includes, so the repo owns `~/.config/cmux/cmux.json` and `~/.config/cmux/dock.json`, backing up previous copies before replacing changed settings.

## Install

```sh
git clone https://github.com/teamleaderleo/terminal-kit.git ~/Projects/terminal-kit
~/Projects/terminal-kit/install.sh
exec zsh
```

Future updates use either form:

```sh
tk
tk update
```

## Commands

```text
tk / tk update              Pull Git changes, install tools, reload, and refresh Zsh
tk status                   Show branch, stash count, and working-tree state on demand
tk apply                    Apply local files without pulling Git
tk theme                    Browse, test, set, rotate, or automate cmux themes
tk glass                    Switch native macOS glass presets
tk scroll                   Tune cmux wheel and trackpad scroll speed
tk sidebar                  Tune the left workspace sidebar's minimum width
tk editor                   Toggle wrapping or horizontal editor scrolling
tk overview                 Browse every cmux window and workspace in one calm full-screen view
tk hints                    Control optional hints in cmux workspace rows
tk keys                     Print the compact hotkey and command cheat sheet
tk prompt                   Choose minimal, detailed, or disabled prompt mode
tk perf                     Benchmark Zsh and inspect cmux resources
tk memory                   Manual or automatic renderer and agent-memory policy
tk tools                    Install missing Homebrew tools
tk doctor                   Check files, commands, and syntax
tk test                     Run the repo tests
tk edit                     Open the repository
tk uninstall                Remove the managed include blocks
```

## Workspace overview

```text
tk overview                 Open the all-window workspace view
tk overview list            Print the same workspace list as plain text
```

The overview spans every cmux window. It uses active, selected, and idle markers; aligned workspace labels; restrained bold and dim text; a rounded inset frame; and a metadata and pane-tree preview. It inherits the active terminal palette without fixed interface colours. Type to filter, press Enter to focus a workspace, or press Esc to return.

This is the keyboard-first terminal-kit version of an Exposé-style view. Live thumbnails, animated zoom, and pointer selection require native workspace snapshots and an AppKit overview inside cmux.

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

## Memory controls

The effective memory policy lives in `~/.config/terminal-kit/memory-mode`, outside Git. It controls two different mechanisms:

- Renderer reclamation releases off-screen Metal renderers while keeping the shell process, PTY, scrollback, and terminal state alive.
- Agent hibernation stops only supported, restorable coding agents after they are idle and off-screen. Ordinary shells and arbitrary running commands are never killed.

```text
tk memory status       Show the active policy, automatic state, and limits
tk memory auto on      Follow native macOS memory-pressure events
tk memory auto off     Stop automatic changes and keep the current mode
tk memory auto log     Show recent pressure transitions
tk memory normal       cmux defaults: 12 warm renderers; agents remain live
tk memory balanced     6 warm renderers; agents remain live
tk memory lean         2 warm renderers; hibernate agents above 4
tk memory ultra        1 warm renderer; hibernate agents above 2
tk memory menu         Interactive memory control
tk memory top          cmux Task Manager by workspace and surface
```

Automatic mode compiles a tiny native Swift daemon and installs it as the per-user LaunchAgent `com.terminal-kit.memory-auto`. It sleeps on a Grand Central Dispatch memory-pressure source rather than polling:

```text
macOS normal for 5 minutes  → balanced
macOS warning               → lean immediately
macOS critical              → ultra immediately
```

The five-minute recovery delay prevents rapid mode flapping. Manual selection of `normal`, `balanced`, `lean`, or `ultra` disables automatic mode. The controller state lives in `~/.config/terminal-kit/memory-auto`, and transitions are logged to `~/Library/Logs/terminal-kit-memoryd.log`.

Balanced remains the default until automatic mode is explicitly enabled. Lean and Ultra trade a small tab-switch warm-up for a lower idle footprint when many workspaces and agent sessions are open. The cmux Dock includes a clickable **Memory** control, and the Command Palette includes automatic on/off, each preset, and Task Manager.

cmux itself also performs coordinated memory-pressure reclamation and cold scrollback compression. The terminal-kit daemon does not replace those mechanisms; it changes the configurable renderer and agent caps when macOS reports system pressure.

Cloud VMs are remote compute rather than local terminal processes. cmux exposes list, create, attach, execute, and destroy operations; provider idle suspension is automatic rather than a local RAM toggle. The Command Palette includes **Cloud VMs: List** for quick inspection.

## Performance measurement

```text
tk perf status       Show cmux version and performance-related settings
tk perf shell        Benchmark bare versus configured Zsh startup
tk perf profile      Profile Zsh startup functions with zprof
tk perf cmux         Show cmux resource use by window, workspace, and surface
tk perf all          Run the main reports
```

Hyperfine supplies repeatable shell benchmarks. `cmux top` identifies the actual workspace, browser pane, terminal process, or coding agent responsible when the app feels slow.

## Sidebar width

cmux's left workspace sidebar is draggable, but its normal minimum is 240 points. terminal-kit can lower that resize limit without patching cmux:

```text
tk sidebar current    Show the current minimum
tk sidebar compact    Allow shrinking to 180 points
tk sidebar tiny       Allow shrinking to 140 points
tk sidebar normal     Restore 240 points
tk sidebar set 165    Set a custom 120–260 point minimum
tk sidebar reset      Remove the override
```

The setting changes the lower limit rather than forcing a width. Fully quit and reopen cmux, then drag the divider between the sidebar and terminal.

## Calm workspace defaults

New top-level workspaces start in the user's home directory (`~`) rather than inheriting whichever project happened to be focused. Opening an explicit project path still starts there, and work inside an existing project keeps its own context.

The left sidebar defaults to one calm title row. It hides the duplicated branch/directory line, pull-request snippets, ports, logs, progress rows, and notification text. Agent activity and unread badges remain available. The selected workspace uses Catppuccin Mocha's muted surface colour instead of the macOS accent-blue fallback.

The hidden Git metadata watcher is disabled, because the sidebar no longer displays branch or pull-request information.

## Horizontal views

Normal terminal output keeps wrapping because that is the most readable and compatible behaviour for shells, tmux, and TUIs. Use the opt-in `wide` pager for long rows:

```sh
wide report.txt
ps aux | wide
git diff --stat | wide
```

`wide` runs `less -R -S`; use Left/Right arrows to move sideways and `q` to close it.

cmux's built-in text editor has a separate persistent mode:

```text
tk editor current     Show the active mode
tk editor wrap        Wrap long lines at the right edge
tk editor wide        Keep one row per line and scroll horizontally
tk editor toggle      Switch modes
```

The editor preference lives in `~/.config/terminal-kit/editor-wrap`, outside Git, and is reapplied during updates.

## Keys and optional hints

Automatic workspace-row hints are off by default. cmux status metadata is supplied only after Zsh starts, so automatic hints visibly changed row height after a workspace had already appeared. The stable help view is:

```text
tk keys
```

Optional explicit controls remain available:

```text
tk hints current      Show whether automatic hints are enabled
tk hints next         Place one hint in the current workspace row
tk hints clear        Remove the current workspace hint
tk hints on           Re-enable automatic fresh-shell hints
tk hints off          Disable automatic hints
```

The preference lives in `~/.config/terminal-kit/hints`, and the rotation index lives beside it. Both stay outside Git. Native hold-a-modifier shortcut previews remain enabled because they appear on demand without changing sidebar layout.

## Prompt modes

The default Starship prompt is deliberately minimal:

```text
~/Projects/terminal-kit ❯
```

Git branch, stash, and modified-file indicators are not permanently shown. Use `tk status` when those details matter, or switch to the optional detailed prompt:

```text
tk prompt status
tk prompt minimal
tk prompt detailed
tk prompt off
exec zsh
```

The detailed mode shows the Git branch and compact repository state. Both prompt modes use ordinary ANSI colours so they follow the active terminal theme, while failures, long command duration, and background jobs can still appear on the right.

## Modern terminal tools

The kit installs a restrained terminal-native toolbelt:

- `y` opens Yazi and changes the shell directory to the folder selected on exit.
- `lg` opens Lazygit in the current repository.
- `bt` opens btop.
- `rg`, `fd`, and `jq` provide fast content search, file search, and JSON processing.
- `wide` opens files or piped output without wrapping long rows.

Yazi image previews can pass through tmux into Ghostty-compatible terminals. In cmux, `Cmd+Up` and `Cmd+Down` jump between shell prompts instead of scrolling line-by-line through command output.

cmux's Command Palette includes Yazi, Lazygit, btop, themes, glass, scrolling, editor wrapping, compact sidebar mode, prompt modes, automatic memory control, memory presets, Task Manager, Cloud VM listing, optional hints, key previews, readability testing, and the all-window workspace overview. The global Dock provides Memory, System, and Feed panels; a project-local `.cmux/dock.json` can replace it with repo-specific logs, tests, servers, or Git controls.

## Managed files

| Repo file | Loaded by |
| --- | --- |
| `config/ghostty/config` | Ghostty and cmux behaviour, home-directory default, and keybindings |
| `config/ghostty/appearance` | Ghostty and cmux theme fallback and typography |
| `~/.config/terminal-kit/glass.ghostty` | Machine-local native glass preset |
| `~/.config/terminal-kit/scroll-speed` | Machine-local cmux scroll multiplier |
| `~/.config/terminal-kit/prompt` | Machine-local prompt mode |
| `~/.config/terminal-kit/hints` | Machine-local automatic-hint switch |
| `~/.config/terminal-kit/hint-index` | Machine-local hint rotation position |
| `~/.config/terminal-kit/editor-wrap` | Machine-local cmux editor mode |
| `~/.config/terminal-kit/memory-mode` | Machine-local effective renderer and agent-memory policy |
| `~/.config/terminal-kit/memory-auto` | Machine-local automatic memory-controller switch |
| `~/Library/LaunchAgents/com.terminal-kit.memory-auto.plist` | Per-user event-driven memory daemon, only when enabled |
| `tools/memoryd/main.swift` | Native macOS normal/warning/critical pressure listener |
| `config/cmux/cmux.json.example` | Rendered to `~/.config/cmux/cmux.json` with local scroll, editor, and memory settings |
| `config/cmux/dock.json.example` | Synced to `~/.config/cmux/dock.json` |
| `config/hints.txt` | Compact cmux and terminal-kit hint catalogue |
| `config/starship/terminal-kit.toml` | Calm minimal prompt |
| `config/starship/detailed.toml` | Optional Git-detailed prompt |
| `config/tmux/tmux.conf` | `~/.tmux.conf` |
| `config/zsh/env.zsh` | `~/.zshenv`; restores standard macOS and Homebrew command paths early |
| `config/zsh/init.zsh` | Per-shell helper, prompt, optional hint, and plugin bootstrap |
| `config/zsh/terminal.zsh` | Editing widgets, history, and aliases |
| `config/zsh/tools.zsh` | Yazi, wide view, and modern-tool wrappers |
| `config/zsh/hints.zsh` | Opt-in fresh-surface hint display and first-command cleanup hook |
| `config/zsh/highlight.zsh` | Subdued sage, salmon, and indigo syntax colours |
| `scripts/perf.sh` | Shell benchmarks, Zsh profiling, and cmux resource reports |
| `scripts/memory.sh` | Manual presets plus LaunchAgent build and control logic |

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

The base configuration does not fix its own background, foreground, cursor, or selection hex values, so Rosé Pine, Vesper, Catppuccin, and other selected themes can display their full palettes. The cmux sidebar and tmux use theme-responsive backgrounds and restrained companion colours. `bat` uses its `base16` theme and Delta follows `BAT_THEME` where possible.

The built-in Markdown viewer uses a 16-point body size and a narrower reading column, and the plain-text editor defaults to wrapping long lines.

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

The beta cmux TextBox stays hidden for new terminals. Zsh remains the command editor, with Starship only rendering the prompt around it.

## Ricing roadmap

`docs/ricing-roadmap.md` records the broader cmux customisation surface: custom actions, project layouts, Dock controls, browser automation, notifications, workspace metadata, remaining theme gaps, and sensible future upgrades.

## Session behaviour

`tk` reloads the live tmux server without closing sessions, panes, or running programs. It asks cmux and Ghostty to reload their settings. Other open shells pick up shell changes after `exec zsh`, `source ~/.zshrc`, or opening a fresh workspace.

## Public-repo safety

Keep machine credentials and private values outside this repo. Avoid committing tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history. Put machine-specific private additions in your existing local config files outside the managed include blocks.
