# Working on terminal-kit

terminal-kit is a public macOS terminal setup (Ghostty, cmux, tmux, Zsh) plus `tk do`, a launcher that runs coding agents in owned Git worktrees.

- Settings: `scripts/settings.py` is the only writer of `~/.config/cmux/cmux.json` and the glass include. Add a key there instead of editing cmux.json anywhere else.
- Host files get managed include blocks (`scripts/lib.sh`); never replace a whole host file.
- Nothing may override keys outside the Zsh prompt, and nothing may write the clipboard unless the user asked. See `docs/interaction-model.md`.
- The brief given to `tk do` agents lives in `agent_brief` in `scripts/work-lib.sh`.
- Keep user-facing text short and plain. Prefer deleting a feature over adding a knob.
- Tests are behavioural and run against a fake HOME. Run `bash scripts/test-all.sh` (same as `tk test` and CI) before committing. Tests must never reload or restart the live cmux, Ghostty, or tmux; they set `TERMINAL_KIT_NO_RELOAD=1`.
