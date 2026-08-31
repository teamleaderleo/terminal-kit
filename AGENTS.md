# terminal-kit agent entry point

**Protocol:** `terminal-kit-agent/v1`  
**Machine policy:** `config/agent-policy.json`

terminal-kit is the low-ceremony front door for agent work across repositories while also managing Ghostty, cmux, tmux, Zsh, and portable keyboard settings.

## Bootstrap

Before substantive work:

1. Read `config/agent-policy.json`.
2. Run `terminal-kit agent context --json` when available.
3. Read the target repository guidance and current diff.
4. Own a meaningful outcome and continue through covered executable steps.

`tk do` is the primary human-facing work entrypoint. For tasks launched through it, compose the target repository's `AGENTS.md`, `CLAUDE.md`, `STENSIBLY.md`, `CONTRIBUTING.md`, bootstrap/package scripts, Makefiles, and CI commands.

## Canonical policy and invariants

`config/agent-policy.json` is canonical for autonomous actions, approval-required consequence classes, evidence rules, exact cleanup ownership, task recovery, agent interfaces, and handoff fields. Consume those fields directly instead of copying their lists into prose.

- Preserve user changes and running terminal processes. Task work belongs in terminal-kit-owned worktrees; [`scripts/work.sh`](scripts/work.sh) owns receipt, undo, restore, and hidden recovery-ref behavior.
- Keep `tk do` and ordinary human commands low-ceremony; agent-facing JSON and receipts may be richer.
- Exact GitHub handoff should prefer `gh ... --json ... --jq ...` or `--template`; terminal tables, colours, and visual wrapping are presentation.
- The saved GitHub Git transport is handled by [`scripts/git.sh`](scripts/git.sh): SSH is the default preference, explicit URLs keep their protocol, and browser/API links use HTTPS.
- Preserve Command-C/Command-V clipboard behavior and Control-C interruption. Navigation semantics live in [`docs/interaction-model.md`](docs/interaction-model.md).
- Keep user-facing settings in `config/`. Preserve the include-based installer and avoid replacing complete host config files or sending commands into existing tmux panes.
- cmux shortcut semantics belong in `config/cmux/cmux.json.example`. macOS-only translation belongs in `config/karabiner/terminal-kit.json`; portable Karabiner export rules live in [`config/karabiner/README.md`](config/karabiner/README.md).

## Task state

Use `tk agent context --json` for bootstrap and `tk agent checkpoint <state> [summary] [--proof text] [--next text]` for durable progress. Use `working`, `needs-attention`, `review`, and `done` as work advances. The operator does not maintain checkpoint state manually.

## Checks

Run before committing:

```sh
./scripts/test.sh
./scripts/test-agent.sh
./scripts/test-karabiner.sh
```

On macOS with the tools installed, also run `terminal-kit doctor` and `terminal-kit apply`.

## Completion

Leave durable state that gives a fresh agent the result, proof, next executable action, exact repository/work reference when useful, and recovery information.
