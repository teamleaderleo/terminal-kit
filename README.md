# terminal-kit

A small public MIT-licensed macOS dotfiles repo for Ghostty, cmux, tmux, and Zsh.

The checkout lives at `~/Projects/terminal-kit`. The installer adds managed include blocks to existing shell, tmux, and Ghostty host files. cmux lacks config includes, so terminal-kit owns `~/.config/cmux/cmux.json` and `~/.config/cmux/dock.json` and backs up changed copies before replacement.

## Install and update

```sh
git clone git@github.com:teamleaderleo/terminal-kit.git ~/Projects/terminal-kit
~/Projects/terminal-kit/install.sh
exec zsh
```

Then use `tk` or `tk update` for the normal pull/install/reload path. `tk apply` reapplies the current checkout without pulling; `tk doctor` checks the installation; `tk test` runs repository checks.

## Work with an agent

`tk do` is the primary human work entrypoint:

```text
tk do fix the failing tests
tk do owner/repo#123
tk do https://github.com/owner/repo/pull/456 "finish the review fixes"
```

Git tasks run in terminal-kit-owned worktrees. Current tracked and untracked changes are copied into the task checkout while the source checkout stays put. Durable receipts live under `~/.local/state/terminal-kit/work/`; owned worktrees live under `~/.local/share/terminal-kit/worktrees/`.

```text
tk work list
tk work show [id|last]
tk work path [id|last]
tk work undo [id|last]
tk work restore [id|last]
```

`undo` validates the recorded worktree and branch, creates hidden Git recovery refs, then removes only that owned checkout. `restore` reconstructs it from the receipt and recovery refs. See [managed state and recovery](docs/managed-state.md) and the machine policy in [`config/agent-policy.json`](config/agent-policy.json).

Agents bootstrap with `tk agent context --json` and record durable progress with `tk agent checkpoint`.

## Command families

| Family | Commands | Narrow owner |
| --- | --- | --- |
| Update and repair | `tk`, `tk update`, `tk apply`, `tk tools`, `tk doctor`, `tk test`, `tk uninstall` | [`bin/terminal-kit`](bin/terminal-kit), [`scripts/apply.sh`](scripts/apply.sh), [`scripts/doctor.sh`](scripts/doctor.sh) |
| Work and agent state | `tk do`, `tk work`, `tk agent` | [`scripts/work.sh`](scripts/work.sh), [`scripts/agent.sh`](scripts/agent.sh), [`config/agent-policy.json`](config/agent-policy.json) |
| Git and clipboard | `tk status`, `tk git`, `tk copy` | [`scripts/git.sh`](scripts/git.sh), [`scripts/copy.sh`](scripts/copy.sh) |
| cmux controls | `tk theme`, `tk glass`, `tk scroll`, `tk sidebar`, `tk editor`, `tk overview`, `tk hints`, `tk keys` | [`scripts/theme.sh`](scripts/theme.sh), [`scripts/glass.sh`](scripts/glass.sh), [`scripts/scroll.sh`](scripts/scroll.sh), [`scripts/sidebar.sh`](scripts/sidebar.sh), [`scripts/editor.sh`](scripts/editor.sh), [`scripts/overview.sh`](scripts/overview.sh), [`scripts/hints.sh`](scripts/hints.sh) |
| Shell and resources | `tk prompt`, `tk perf`, `tk memory` | [`scripts/prompt.sh`](scripts/prompt.sh), [`scripts/perf.sh`](scripts/perf.sh), [`scripts/memory.sh`](scripts/memory.sh) |
| Keyboard mappings | `tk karabiner` | [`config/karabiner/README.md`](config/karabiner/README.md), [`scripts/karabiner.sh`](scripts/karabiner.sh) |
| Repository access | `tk publish`, `tk edit`, `tk path` | [`bin/terminal-kit`](bin/terminal-kit), [`scripts/publish.sh`](scripts/publish.sh) |

`tk keys` is the compact everyday hotkey/command reference.

## GitHub transport

The saved GitHub Git preference defaults to SSH and is stored in `~/.config/terminal-kit/git-protocol`. `tk git ssh` and `tk git https` update the GitHub CLI Git protocol; `tk git current` shows the saved choice.

Explicit Git URLs keep the protocol they specify. terminal-kit removes its legacy global HTTPS-to-SSH rewrite, so HTTPS URLs used by Xcode, SwiftPM, package managers, and scripts remain HTTPS. Browser and API links also use HTTPS. See [`scripts/git.sh`](scripts/git.sh).

`clip remote` copies the configured Git remote; `clip web` copies its browser URL.

## Local state and running processes

Machine-local preferences stay outside Git. The full ownership map, backup directory, task receipts, worktree locations, and recovery refs are documented in [managed state and recovery](docs/managed-state.md).

`tk` reloads the live tmux server while keeping sessions, panes, and running programs alive, then asks cmux and Ghostty to reload settings. Existing shells pick up shell changes after `exec zsh`, `source ~/.zshrc`, or opening a fresh workspace.

Memory controls reclaim off-screen renderers while keeping the shell process, PTY, scrollback, and terminal state alive. Agent hibernation applies only to supported, restorable coding agents; ordinary shells and arbitrary running commands stay live.

## Interaction and appearance

- [Familiar interaction model](docs/interaction-model.md) owns browser/Finder-style navigation and terminal selection constraints.
- [Ricing roadmap](docs/ricing-roadmap.md) owns the broader cmux customization surface.
- [Theme shortlist](docs/theme-shortlist.md) owns the curated theme notes.
- `config/ghostty/`, `config/cmux/`, `config/zsh/`, and `config/starship/` own the active appearance and shell behavior.

## Public-repo safety

Keep machine credentials and private values outside this repo: tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history belong in machine-local config outside terminal-kit-managed blocks.
