# terminal-kit

A small public MIT-licensed macOS dotfiles repo for Ghostty, cmux, tmux, and Zsh.

The Git checkout stays in `~/Projects/terminal-kit`. The installer adds tiny managed include blocks to your existing config files, so personal settings can live beside the managed settings.

## Install from the ZIP

```sh
mkdir -p ~/Projects \
unzip -q ~/Downloads/terminal-kit.zip -d ~/Projects \
cd ~/Projects/terminal-kit \
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
| `config/ghostty/config` | Ghostty and cmux |
| `config/tmux/tmux.conf` | `~/.tmux.conf` |
| `config/zsh/terminal.zsh` | `~/.zshrc` |
| `config/cmux/cmux.json.example` | Starter cmux settings when no cmux file exists |

Backups go to `~/.config/terminal-kit-backups/`.

## Session behaviour

`tk` uses `tmux source-file`, leaving the tmux server, sessions, panes, and running programs open. It asks cmux and Ghostty to reload their settings. The current Zsh refreshes its bindings. Other open shells pick them up after `source ~/.zshrc` or the next fresh shell.

## Public-repo safety

Keep machine credentials and private values outside this repo. Avoid committing tokens, SSH private keys, cloud credentials, work-only hostnames, private aliases, and command history. Put machine-specific private additions in your existing local config files outside the managed include blocks.

## Blue theme

The current theme is deep blue with white text:

```ini
background = #0B2D4D
foreground = #FFFFFF
```

Edit `config/ghostty/config`, commit, push, and run `tk` on each Mac.
