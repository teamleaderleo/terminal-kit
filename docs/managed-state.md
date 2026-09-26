# Managed state

Everything terminal-kit writes outside its own checkout, and how task recovery works.

## Host files

| File | What terminal-kit does |
| --- | --- |
| `~/.zshenv` | Managed block sourcing `config/zsh/env.zsh` |
| `~/.zshrc` | Managed block sourcing `config/zsh/init.zsh`; drops stale `source /tmp/.../env` lines |
| `~/.tmux.conf` | Managed block sourcing `config/tmux/tmux.conf` |
| `~/.config/ghostty/config` and `~/Library/Application Support/com.mitchellh.ghostty/config` | Managed block including `config/ghostty/config`, `config/ghostty/appearance`, and the glass file |
| `~/.config/cmux/cmux.json` | Whole file, rendered by `scripts/settings.py` from `config/cmux/cmux.json.example` plus your settings |
| `~/.config/cmux/dock.json` | Whole file, copied from `config/cmux/dock.json.example` |
| `~/.config/karabiner/karabiner.json` | Adds or refreshes one rule (from `config/karabiner/terminal-kit.json`) in the selected profile; also copies it to `assets/complex_modifications/` |
| `~/.gitconfig`, `gh` config | `tk git` sets the GitHub CLI protocol and removes an old global HTTPS-to-SSH rewrite |
| `~/.local/bin/terminal-kit` | Symlink to `bin/terminal-kit` |

A managed block sits between `# >>> terminal-kit: NAME >>>` and `# <<< terminal-kit: NAME <<<`. Everything outside it is yours.

Before replacing a file, terminal-kit copies it to `~/.config/terminal-kit-backups/<timestamp>/`.

## Local state

| Path | Contents |
| --- | --- |
| `~/.config/terminal-kit/settings.json` | `tk set` choices that differ from the defaults |
| `~/.config/terminal-kit/glass.ghostty` | Generated from the `glass` setting |
| `~/.config/terminal-kit/git-protocol` | `ssh` or `https` |
| `~/.config/terminal-kit/recent-organization.json` | `tk recent` pins and groups |
| `~/.local/state/terminal-kit/work/` | `tk do` task receipts and checkpoint events |
| `~/.local/share/terminal-kit/worktrees/` | Task worktrees |
| `~/.cache/terminal-kit/` | Shell startup caches (safe to delete) |

## Task recovery

`tk work undo [id|last]` removes a task worktree only if it still matches its receipt (same path, same branch). First it saves the worktree HEAD to `refs/terminal-kit/recovery/<id>/head` and, if there are uncommitted changes, a snapshot to `refs/terminal-kit/recovery/<id>/snapshot`. If the snapshot cannot be made, nothing is removed.

`tk work restore [id|last]` recreates the branch and worktree from those refs. It stops if the path or branch already exists. A conflict while re-applying the snapshot leaves the worktree for you to resolve and marks the receipt `restore-conflict`.
