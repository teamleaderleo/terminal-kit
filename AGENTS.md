# terminal-kit agent entry point

**Protocol:** `terminal-kit-agent/v1`  
**Machine policy:** `config/agent-policy.json`

terminal-kit manages macOS terminal settings for Ghostty, cmux, tmux, and Zsh, and now acts as the local front door for low-ceremony agent work. The human should be able to point at a repository, file, issue, pull request, or desired outcome and let agents compose the existing tools behind the scenes.

## Start here

Before substantive terminal-kit work:

1. Read `config/agent-policy.json`.
2. Run `terminal-kit agent context --json` when the command is available.
3. Read the relevant repository guidance and current diff.
4. Own a meaningful outcome and continue through covered executable steps without asking for another prompt merely because one command finished.

For work launched through `tk do`, prefer the target repository's own `AGENTS.md`, `CLAUDE.md`, `STENSIBLY.md`, `CONTRIBUTING.md`, bootstrap scripts, package scripts, Makefiles, and CI commands. terminal-kit should compose those interfaces, not become another pipeline language.

## User preferences

- Keep the default appearance simple: deep blue background and white text.
- Preserve Command-C and Command-V for the macOS clipboard.
- Preserve Control-C for process interruption.
- Prefer one-command updates through `tk`.
- Keep running tmux sessions and terminal processes alive during updates.
- Keep the human command surface tiny; agent-facing JSON and receipts may be richer.

## Operator direction

The operator has explicitly asked participating agents to design terminal-kit for agent ergonomics and to handle ordinary reversible implementation work without requiring the operator to learn or supervise the command surface.

Reviewed, reversible repository work may proceed through implementation, checks, self-review, branch/commit, integration, and merge when repository policy, permissions, and the machine policy allow it. Preserve exact evidence and recovery points.

Fresh operator approval remains required for the consequence classes listed in `config/agent-policy.json`, including material spend, secret exposure, access widening, external publication/contact, destructive non-test data changes, ungranted privileged host mutation, irreversible migration without recovery, and legal or financial effects.

## Design rules

- Keep `tk do` as the primary human-facing work entrypoint.
- Prefer stable JSON and explicit receipts for agent-facing state.
- Treat pretty TTY tables, colours, and visual wrapping as presentation only. They are poor evidence transport across terminal selection, clipboard, and chat.
- When exact GitHub values need to leave the terminal, prefer `gh ... --json ... --jq ...` or `--template` on the first attempt rather than asking the operator to copy a `gh` table and repairing the handoff afterward.
- When asking the operator to run a command and return output, choose compact stable plain text or JSON that remains meaningful after colour and layout disappear and that is unlikely to soft-wrap.
- Keep ordinary human commands as escape hatches, not ceremony agents force the operator to remember.
- Preserve user changes. Agent task work belongs in terminal-kit-owned worktrees by default.
- Every automatic cleanup must prove it owns the exact resource it removes.
- Recovery should survive a dead terminal, dead chat, or abandoned agent session.
- Use cmux as presentation: workspace state, attention, completion, and notifications may mirror durable terminal-kit state.
- Keep durable truth in terminal-kit receipts/events or the target repository, not only in transient cmux UI.
- Prefer existing mature tools (`git`, `gh`, cmux, provider CLIs) over reimplementing their protocols.
- Add dependencies only when they materially reduce complexity or failure risk.

## Editing rules

- Keep user-facing settings in `config/`.
- Preserve the include-based installer; avoid replacing the user's complete `.zshrc`, `.tmux.conf`, or Ghostty host files.
- Keep installer runs repeatable.
- Back up host files before changing managed blocks.
- Avoid sending commands into existing tmux panes.
- Keep cmux TextBox focus disabled by default so terminal signals remain direct.

## Task state

Agents working in a terminal-kit task should use:

```text
tk agent context --json
tk agent checkpoint working "what is being done"
tk agent checkpoint needs-attention "exact blocker" --next "clearing condition"
tk agent checkpoint review "implementation complete" --proof "checks run"
tk agent checkpoint done "outcome complete" --proof "exact checks/evidence" --next "useful continuation, if any"
```

The checkpoint interface exists for agents and automation. The operator never needs to maintain it manually.

## Checks

Run before committing:

```sh
./scripts/test.sh
```

On macOS with the tools installed, also run:

```sh
terminal-kit doctor
terminal-kit apply
```

## Completion

A useful run leaves durable state another fresh agent can understand: current state, plain-language result, proof, next executable action, exact repository/work reference when useful, and recovery information for terminal-kit-owned task work.
