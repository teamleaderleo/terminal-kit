# terminal-kit

A small public MIT-licensed macOS dotfiles repo for Ghostty, cmux, tmux, and Zsh.

The Git checkout stays in `~/Projects/terminal-kit`. The installer adds tiny managed include blocks to your existing shell, tmux, and Ghostty files. cmux does not support config includes, so the repo owns `~/.config/cmux/cmux.json` and backs up the previous copy before replacing changed settings.

## Install from the ZIP

```sh
unzip -q ~/Downloads/terminal-kit.zip -d ~/Projects
cd ~/Projects/terminal-kit
./install.sh
```

Open one fresh shell. Future updates use one command:

```sh
tk
```

## Publish to GitHub

The repo already contains an MIT licence and a conservative `.gitignore` for common secret files.

Let the helper create a public repository:

```sh
cd ~/Projects/terminal-kit
terminal-kit publish terminal-kit
```

Or create an empty public GitHub repo in the browser, then connect it:

```sh
cd ~/Projects/terminal-kit
git init -b main
git add .
git commit -m "Add terminal settings"
git remote add origin git@github.com:YOUR_GITHUB_USERNAME/terminal-kit.git
git push -u origin main
```

A fresh Mac can then use:

```sh
git clone git@github.com:YOUR_GITHUB_USERNAME/terminal-kit.git ~/Projects/terminal-kit \
  && ~/Projects/terminal-kit/install.sh
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

## Session behaviour

`tk` uses `tmux source-file`, leaving the tmux server, sessions, panes, and running programs open. It asks cmux and Ghostty to reload their settings. The current Zsh refreshes its bindings. Other open shells pick them up after `source ~/.zshrc` or the next fresh shell.

## Public-repo safety

Keep machine credentials and private values outside this repo. Avoid committing tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history. Put machine-specific private additions in your existing local config files outside the managed include blocks.

## Calm lavender theme

The current appearance uses Catppuccin Macchiato as its ANSI palette with a darker, desaturated lavender base:

```ini
theme = Catppuccin Macchiato
background = #1E1A2B
foreground = #DAD7E5
cursor-color = #C6A0F6
```

The cmux sidebar uses a matching lavender tint and a subdued selected-workspace wash. The beta TextBox is hidden by default, removing the large `Prompt or command` field.

Edit the managed files, commit, push, and run `tk` on each Mac.
