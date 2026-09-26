# terminal-kit

A public MIT-licensed macOS terminal environment and agent-work launcher for Ghostty, cmux, tmux, and Zsh. It keeps the everyday terminal setup reproducible while giving coding-agent tasks isolated Git worktrees, durable handoffs, and recovery paths.

The checkout lives at `~/Projects/terminal-kit`. The installer adds managed include blocks to existing shell, tmux, and Ghostty host files. cmux lacks config includes, so terminal-kit owns `~/.config/cmux/cmux.json` and `~/.config/cmux/dock.json` and backs up changed copies before replacement.

## Install and update

```sh
git clone git@github.com:teamleaderleo/terminal-kit.git ~/Projects/terminal-kit
~/Projects/terminal-kit/install.sh
exec zsh
```

`tk update` fetches, shows the incoming commits, fast-forwards, and reinstalls; `tk update --check` only shows. Then run `exec zsh`. `tk apply` reapplies local settings without fetching; `tk doctor` checks the installation.

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

`undo` validates the recorded worktree and branch, creates hidden Git recovery refs, then removes only that owned checkout. `restore` reconstructs it from the receipt and recovery refs. See [managed state and recovery](docs/managed-state.md).

Each agent gets a short brief (`tk agent policy`); it can read its task with `tk agent context --json` and record progress with `tk agent checkpoint`.

## Command families

| Family | Commands | Narrow owner |
| --- | --- | --- |
| Update and repair | `tk`, `tk update`, `tk apply`, `tk tools`, `tk doctor`, `tk test`, `tk uninstall` | [`bin/terminal-kit`](bin/terminal-kit), [`scripts/apply.sh`](scripts/apply.sh), [`scripts/doctor.sh`](scripts/doctor.sh) |
| Work and agent state | `tk do`, `tk work`, `tk agent` | [`scripts/work.sh`](scripts/work.sh), [`scripts/agent.sh`](scripts/agent.sh) |
| Git and clipboard | `tk status`, `tk git`, `tk copy` | [`scripts/git.sh`](scripts/git.sh), [`scripts/copy.sh`](scripts/copy.sh) |
| Settings | `tk set` (scroll, wrap, prompt, memory, sidebar, glass) | [`scripts/settings.py`](scripts/settings.py) |
| cmux controls and fork | `tk theme`, `tk overview`, `tk hints`, `tk keys`, `tk cmux` | [`scripts/theme.sh`](scripts/theme.sh), [`scripts/overview.sh`](scripts/overview.sh), [`scripts/hints.sh`](scripts/hints.sh), [`scripts/cmux-fork.sh`](scripts/cmux-fork.sh) |
| Shell and resources | `tk perf` | [`scripts/perf.sh`](scripts/perf.sh) |
| Keyboard mappings | `tk karabiner` | [`config/karabiner/README.md`](config/karabiner/README.md), [`scripts/karabiner.sh`](scripts/karabiner.sh) |
| Repository access | `tk publish`, `tk edit`, `tk path` | [`bin/terminal-kit`](bin/terminal-kit), [`scripts/publish.sh`](scripts/publish.sh) |

`tk keys` is the compact everyday hotkey/command reference.

## GitHub transport

The saved GitHub Git preference defaults to SSH and is stored in `~/.config/terminal-kit/git-protocol`. `tk git ssh` and `tk git https` update the GitHub CLI Git protocol; `tk git current` shows the saved choice.

Explicit Git URLs keep the protocol they specify. terminal-kit removes its legacy global HTTPS-to-SSH rewrite, so HTTPS URLs used by Xcode, SwiftPM, package managers, and scripts remain HTTPS. Browser and API links also use HTTPS. See [`scripts/git.sh`](scripts/git.sh).

`clip remote` copies the configured Git remote; `clip web` copies its browser URL.

## Local state and running processes

Shell shortcuts use opt-in names: `ll` lists with eza, `lg` opens lazygit, `bt` opens btop, and `findf` searches with fd when installed. Standard commands such as `ls`, `tree`, and `cat` retain their native behavior. Use `eza --tree`, `bat`, or `grc COMMAND` explicitly for enhanced output.

Shell startup preserves the incoming `PATH` order, including activated Python environments and other toolchains, and appends any missing local, Homebrew, and system directories.

After upgrading from the old aliases, open a new shell (or run `exec zsh`). Sourcing the config does not remove aliases or wrappers already loaded in a running shell.

Machine-local preferences stay outside Git. The full ownership map, backup directory, task receipts, worktree locations, and recovery refs are documented in [managed state and recovery](docs/managed-state.md).

`tk` reloads the live tmux server while keeping sessions, panes, and running programs alive, then asks cmux and Ghostty to reload settings. Existing shells pick up shell changes after `exec zsh`, `source ~/.zshrc`, or opening a fresh workspace.

`tk set memory lean` makes cmux release off-screen renderers sooner and hibernate idle, restorable coding agents; shells and running commands stay live. `normal` is the default.

## Interaction and appearance

- [Familiar interaction model](docs/interaction-model.md) owns browser/Finder-style navigation and terminal selection constraints.
- [Ricing roadmap](docs/ricing-roadmap.md) owns the broader cmux customization surface.
- [Native builds](docs/native-builds.md) explains the canonical cmux checkout, Glaeda warm builds, and explicit update/launch flows.
- [Theme shortlist](docs/theme-shortlist.md) owns the curated theme notes.
- `config/ghostty/`, `config/cmux/`, `config/zsh/`, and `config/starship/` own the active appearance and shell behavior.

## Public-repo safety

Keep machine credentials and private values outside this repo: tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history belong in machine-local config outside terminal-kit-managed blocks.

### Claude and Codex together

Run `tk duo /path/to/project` (or `tk duo` from the project) to open a new, evenly split cmux workspace with Claude on the left and Codex on the right. It uses the ordinary installed CLIs and their normal sign-in, directory-trust and approval flows. Existing sessions are left open. Both agents see the same checkout: the layout does not isolate edits, synchronize conversations or assign work. Give overlapping edits to one agent at a time, or use separate worktrees.

This first trial tests direct access to both agents around one project. Next experiments: unmistakable keyboard focus, enlarging one pane without losing the pair, and visible pending input even when sidebar detail is hidden. Measure switching and scrolling with real activity before changing animation or renderer budgets.

### Recent conversations (local trial)

`tk recent` opens a compact searchable Claude/Codex history picker. Type a project,
title or provider, use arrows to select, and Enter to resume in a new cmux workspace.
The list refreshes every 15 seconds; Ctrl-R refreshes immediately; Escape closes. `tk recent --json` returns metadata for a future
sidebar adapter. `--cmux /path/to/tag-cli` targets an isolated development build.

The picker reads local client history without modifying it. It uses exact session
IDs and the recorded project directory. It does not synchronize cloud-only chats,
import T3 history, detect clients already running elsewhere, or claim all desktop
sessions are CLI-compatible. Normal client trust prompts remain in place. Do not
resume a conversation already executing in another client.

Discovery considers the newest 200 files per provider and returns up to 200 rows.
Transcript reads are bounded to the first/last 128 KiB; missing titles appear as
Untitled conversation. Claude sidechain directories and Codex archived sessions
are excluded. Titles/paths are private local metadata; JSON output contains them.
This is the live-history/resume prototype, not yet the native sidebar.

The recent-work trial now starts in **Grouped** view. Codex saved desktop project
assignments and pin order are read locally (including pins outside the recent
cutoff). Claude falls back to explicitly labelled recorded working folders; Claude
desktop pins/custom groups are not imported. Saved desktop metadata may lag the
application; this does not claim a live cloud synchronization API.

Use **Ctrl-P** to toggle a workbench pin, **Ctrl-G** to assign a mixed-provider
group (blank restores source grouping), **Ctrl-U** to restore the source pin,
and **Ctrl-O** to switch between stable grouped order and recency. Search includes
group names. Local choices persist privately in
`~/.config/terminal-kit/recent-organization.json` and never write back to either
provider. Changes use a lock and atomic replacement; invalid state is preserved.
Manual reordering and collapsing groups are not yet implemented.

### Native Work sidebar

`tk recent --sidebar` refreshes the history snapshot and selects **tk-work** in
cmux's actual left sidebar. Use the tagged `--cmux` wrapper for dev builds. The
existing terminal picker remains available for editing persistent groups/pins.

The native view has compact conversation buttons, collapsible headings, search
and a Recents switch. It focuses live agent surfaces using exact session IDs and
hosting panel IDs. Unknown ownership opens an inline choice; only the explicit
resume button launches a client. New launches carry a stable conversation marker
so later clicks focus that workspace. The client still enforces its session lock.
Repeated clicks are suppressed while creation is pending. A failed request can
be retried by refreshing the sidebar; inline socket error reporting remains a gap.

Live surface/focus state updates automatically. History itself is a snapshot,
refreshed by rerunning the command; selection, search and collapse state reset
on refresh. Native group editing, persistent collapse/order and automatic history
refresh remain follow-up work. Choose **Default Workspaces** from cmux's sidebar
menu to return to the standard sidebar. No session is closed by switching views.

Hover-stall investigation: Default Workspaces is responsive; Work with its
custom hover wash disabled also stopped the reported symptom. The wash remains
disabled as a temporary mitigation, not a finished interaction. A proposed native
tracking-layer replacement was parked after its package change triggered a broad
app rebuild. Do not treat the earlier lookup benchmark or fade removal as an
end-to-end fix for the reported beachball.
