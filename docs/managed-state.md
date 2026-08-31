# Managed state and recovery

This document owns terminal-kit's cross-cutting file/state map and task recovery paths. Command-family behavior stays with the corresponding scripts.

## Host-file ownership

The installer keeps the Git checkout at `~/Projects/terminal-kit` and adds small managed include blocks to existing shell, tmux, and Ghostty host files. It preserves the rest of those files. cmux has no config-include mechanism, so terminal-kit owns the rendered `~/.config/cmux/cmux.json` and `~/.config/cmux/dock.json` files.

Backups created while changing managed host state go to `~/.config/terminal-kit-backups/`.

## Repo and machine-local state

| Repo or local file | Role / loaded by |
| --- | --- |
| `config/ghostty/config` | Ghostty and cmux behavior, home-directory default, and keybindings |
| `config/ghostty/appearance` | Ghostty and cmux theme fallback and typography |
| `~/.config/terminal-kit/glass.ghostty` | Machine-local native glass preset |
| `~/.config/terminal-kit/scroll-speed` | Machine-local cmux scroll multiplier |
| `~/.config/terminal-kit/prompt` | Machine-local prompt mode |
| `~/.config/terminal-kit/hints` | Machine-local automatic-hint switch |
| `~/.config/terminal-kit/hint-index` | Machine-local hint rotation position |
| `~/.config/terminal-kit/editor-wrap` | Machine-local cmux editor mode |
| `~/.config/terminal-kit/git-protocol` | Machine-local GitHub Git transport choice |
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
| `config/zsh/env.zsh` | `~/.zshenv`; restores command paths and friendly editor defaults early |
| `config/zsh/init.zsh` | Per-shell helper, prompt, completion, pager, optional hint, and plugin bootstrap |
| `config/zsh/terminal.zsh` | Editing widgets, history, and aliases |
| `config/zsh/tools.zsh` | Yazi, wide view, clipboard, and modern-tool wrappers |
| `config/zsh/hints.zsh` | Opt-in fresh-surface hint display and first-command cleanup hook |
| `config/zsh/highlight.zsh` | Subdued sage, salmon, and indigo syntax colours |
| `scripts/git.sh` | Saved GitHub SSH/HTTPS preference and legacy rewrite cleanup |
| `scripts/perf.sh` | Shell benchmarks, Zsh profiling, and cmux resource reports |
| `scripts/memory.sh` | Manual presets plus LaunchAgent build and control logic |

## Agent task receipts and recovery

`tk do` / `tk work` keeps durable task receipts in `~/.local/state/terminal-kit/work/` and creates owned task worktrees under `~/.local/share/terminal-kit/worktrees/` by default.

`tk work undo [id|last]` removes only a receipt-recorded disposable worktree. Before removal it verifies that the path is still the recorded Git worktree and that its branch still matches the receipt. It records the worktree HEAD at `refs/terminal-kit/recovery/<id>/head`; dirty work also gets a snapshot ref at `refs/terminal-kit/recovery/<id>/snapshot`. If a snapshot cannot be created, the worktree stays in place.

`tk work restore [id|last]` recreates the recorded branch and worktree from those refs. Existing conflicting paths or branches stop restoration. A snapshot-application conflict leaves the recreated worktree in place for manual resolution and records `restore-conflict` in the receipt.

`tk agent checkpoint` appends durable state/events to the same task state so a fresh agent can continue after a dead terminal or abandoned chat.
