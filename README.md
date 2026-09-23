# terminal-kit

A public MIT-licensed macOS terminal environment and agent-work launcher for Ghostty, cmux, tmux, and Zsh. It keeps the everyday terminal setup reproducible while giving coding-agent tasks isolated Git worktrees, durable handoffs, and recovery paths.

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
| cmux controls and fork | `tk theme`, `tk glass`, `tk scroll`, `tk sidebar`, `tk editor`, `tk overview`, `tk hints`, `tk keys`, `tk cmux` | [`scripts/theme.sh`](scripts/theme.sh), [`scripts/glass.sh`](scripts/glass.sh), [`scripts/scroll.sh`](scripts/scroll.sh), [`scripts/sidebar.sh`](scripts/sidebar.sh), [`scripts/editor.sh`](scripts/editor.sh), [`scripts/overview.sh`](scripts/overview.sh), [`scripts/hints.sh`](scripts/hints.sh), [`scripts/cmux-fork.sh`](scripts/cmux-fork.sh) |
| Shell and resources | `tk prompt`, `tk perf`, `tk memory` | [`scripts/prompt.sh`](scripts/prompt.sh), [`scripts/perf.sh`](scripts/perf.sh), [`scripts/memory.sh`](scripts/memory.sh) |
| Keyboard mappings | `tk karabiner` | [`config/karabiner/README.md`](config/karabiner/README.md), [`scripts/karabiner.sh`](scripts/karabiner.sh) |
| Repository access | `tk publish`, `tk edit`, `tk path` | [`bin/terminal-kit`](bin/terminal-kit), [`scripts/publish.sh`](scripts/publish.sh) |

`tk keys` is the compact everyday hotkey/command reference.

## GitHub transport

The saved GitHub Git preference defaults to SSH and is stored in `~/.config/terminal-kit/git-protocol`. `tk git ssh` and `tk git https` update the GitHub CLI Git protocol; `tk git current` shows the saved choice.

Explicit Git URLs keep the protocol they specify. terminal-kit removes its legacy global HTTPS-to-SSH rewrite, so HTTPS URLs used by Xcode, SwiftPM, package managers, and scripts remain HTTPS. Browser and API links also use HTTPS. See [`scripts/git.sh`](scripts/git.sh).

`clip remote` copies the configured Git remote; `clip web` copies its browser URL.

## Local state and running processes

Shell shortcuts use opt-in names: `ll` lists with eza, `lg` opens lazygit, `bt` opens btop, and `findf` searches with fd when installed. Standard commands such as `ls`, `tree`, and `cat` retain their native behavior. Use `eza --tree`, `bat`, or `grc COMMAND` explicitly for enhanced output.

After upgrading from the old aliases, open a new shell (or run `exec zsh`). Sourcing the config does not remove aliases or wrappers already loaded in a running shell.

Machine-local preferences stay outside Git. The full ownership map, backup directory, task receipts, worktree locations, and recovery refs are documented in [managed state and recovery](docs/managed-state.md).

`tk` reloads the live tmux server while keeping sessions, panes, and running programs alive, then asks cmux and Ghostty to reload settings. Existing shells pick up shell changes after `exec zsh`, `source ~/.zshrc`, or opening a fresh workspace.

Memory controls reclaim off-screen renderers while keeping the shell process, PTY, scrollback, and terminal state alive. Agent hibernation applies only to supported, restorable coding agents; ordinary shells and arbitrary running commands stay live.

## Interaction and appearance

- [Familiar interaction model](docs/interaction-model.md) owns browser/Finder-style navigation and terminal selection constraints.
- [Ricing roadmap](docs/ricing-roadmap.md) owns the broader cmux customization surface.
- [Native builds](docs/native-builds.md) explains the canonical cmux checkout, Glaeda warm builds, and explicit update/launch flows.
- [Theme shortlist](docs/theme-shortlist.md) owns the curated theme notes.
- `config/ghostty/`, `config/cmux/`, `config/zsh/`, and `config/starship/` own the active appearance and shell behavior.

## Public-repo safety

Keep machine credentials and private values outside this repo: tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history belong in machine-local config outside terminal-kit-managed blocks.

### Turn the cmux/Ghostty customization on or off

Use `tk customization off`, `tk customization on`, or `tk customization toggle`.
`tk customization status` reports the current profile. This switches shared
cmux/Ghostty configuration; it does not isolate different cmux app builds.

The first switch saves the current configuration and derives an off profile by
removing matching Terminal Kit preset settings and its Ghostty include blocks.
Unrelated settings and values you customized are retained, so off is not a factory
reset. Later switches preserve edits made independently in both profiles. State
and recovery data live in `~/.config/terminal-kit/customization/`.

Agent credentials, hooks, history, running processes, shell setup, Karabiner and
tmux are unaffected. Select cmux's **Default Workspaces** sidebar separately if a
custom sidebar is active. The command reloads the reachable cmux instance; reload other cmux/Ghostty
instances separately.
Install/apply refuse to reapply customization while the off profile is active.
Python 3 is required. Invalid JSON and symlinked managed config files are rejected
before switching. Keep the saved profile directory to retain the on configuration.

### Sidebar density trials

`tk sidebar quiet` keeps workspace titles and agent attention while hiding descriptions, paths, logs and custom metadata. `tk sidebar details` brings back paths, PRs, ports, progress and descriptions, with notification text limited to one line. Both preserve your theme, shortcuts, Git watching preference and live processes. These are shared cmux settings, not per-window settings. Switch between them from the cmux command palette after installing the updated configuration.

Use these presets with customization on. They deliberately change the listed sidebar visibility preferences; switching presets does not restore earlier custom values. Neither preset changes renderer caching or animation timing, so perceived smoothness is not a measured performance result.

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
