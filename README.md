# terminal-kit

A macOS terminal setup for Ghostty, cmux, tmux, and Zsh, plus `tk do`, which hands a task to a coding agent in its own Git worktree. MIT licensed.

## Install

```sh
git clone git@github.com:teamleaderleo/terminal-kit.git ~/Projects/terminal-kit
~/Projects/terminal-kit/install.sh
exec zsh
```

The installer adds small managed blocks to `~/.zshenv`, `~/.zshrc`, `~/.tmux.conf`, and the Ghostty config, and leaves the rest of those files alone. cmux has no include mechanism, so terminal-kit writes `~/.config/cmux/cmux.json` and `~/.config/cmux/dock.json` (backing up any copy it replaces). `tk uninstall` removes the blocks and the command.

## Update

```sh
tk update           # fetch, show incoming commits, fast-forward, reinstall
tk update --check   # only show what is incoming
exec zsh
```

`tk apply` re-applies local settings without fetching. `tk doctor` checks the install. `tk test` runs the test suite (the same one CI runs).

## Everyday commands

| Command | What it does |
| --- | --- |
| `tk set` | List settings; `tk set <key> <value>` changes one (see below) |
| `tk theme next` / `set` / `browse` / `test` | Switch cmux themes |
| `tk copy <what>` / `clip <what>` | Copy the last command, screen, path, project, branch, commit, remote, web URL, a file, or text |
| `tk recent` | Find and resume Claude/Codex conversations |
| `tk duo [dir]` | Claude and Codex side by side in a new cmux workspace |
| `tk keys` | Hotkey cheat sheet |
| `tk git ssh` / `https` | GitHub CLI transport (SSH by default; explicit URLs keep theirs) |
| `tk perf` | Shell and cmux performance checks |
| `tk karabiner` | Add the Cmd-Shift-] / [ surface-switching rule to Karabiner |

Shell helpers: `y` (yazi), `lg` (lazygit), `bt` (btop), `ll` (eza), `ports`, `after <cmd>` (notify when done), `scratch`, `wide`.

## Settings

| Key | Values | Default |
| --- | --- | --- |
| `scroll` | 0.25 to 4 | 1.4 |
| `wrap` | `wrap`, `wide` | `wrap` |
| `prompt` | `minimal`, `detailed`, `off` | `minimal` |
| `memory` | `normal`, `lean` | `normal` |
| `sidebar` | `quiet`, `details` | `quiet` |
| `glass` | `regular`, `clear`, `immersive`, `opaque` | `regular` |

`tk set <key> default` restores a default. `memory lean` lets cmux free off-screen renderers sooner and hibernate idle, restorable coding agents; shells and running commands stay alive. Prompt changes show up after `exec zsh`.

## Agent work

```text
tk do fix the failing tests
tk do owner/repo#123
tk do https://github.com/owner/repo/pull/456 "finish the review fixes"
tk work list | show | path | undo | restore [id|last]
```

Each task gets its own worktree; uncommitted changes in your checkout are copied in and your checkout is left alone. `undo` removes that worktree after saving hidden recovery refs; `restore` brings it back. The agent gets a short brief (`tk agent policy`) and records progress with `tk agent checkpoint`.

## More

- [Managed state](docs/managed-state.md): every file terminal-kit writes, and task recovery.
- [Interaction model](docs/interaction-model.md): keys, selection, and clipboard rules.
- Keep secrets, private hosts, and personal aliases out of this public repo; put them in your own files outside the managed blocks.
