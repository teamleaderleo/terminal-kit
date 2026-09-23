# Inspected updates and source recovery

`tk update` fetches the current branch's configured remote branch, confirms the
candidate is a fast-forward, checks its diff for whitespace errors, and records
its exact commit, changed paths, diff digest, checkout, branch, base revision,
and remote URL. It does not change checkout files or run the fetched installer.
Review the printed `git diff` command before using `tk update --apply FULL_SHA`.
The SHA must be the complete value printed by the inspection. Application does
not silently create a missing inspection receipt. Changed branch, base, remote,
tracked files, or plan data stop application; inspect again after intentional
changes. Harmless untracked files are allowed. Git refuses an update that would
overwrite an untracked file. An introduced path that already exists on the
filesystem is conservatively refused, including ignored files, case/Unicode
aliases, and case-only renames. Resolve ambiguous renames deliberately outside
the updater; it does not infer that an existing alias is safe to replace.

This is an inspection and source-recovery boundary, not signed release
verification or a complete security review. It does not establish that an
installer is trustworthy. The application step executes the exact inspected
revision's installer, which can install packages, edit host files, restart
services, and reload settings. Source archives must use `tk install` explicitly;
`tk update` requires Git history and a named remote branch upstream.

Before applying, terminal-kit saves the previous and candidate commits in
`refs/terminal-kit/updates/`, copies the running updater independently of the
checkout, and records a receipt under the checkout's Git metadata directory,
`terminal-kit-update/recovery-*/`. It prints the exact receipt path and recovery
command **before** running the installer. Keep that output if investigating a
failed update. Linked worktrees have separate receipt directories. The saved
previous revision is the source that was present before the update; it is not a
claim that the prior installation was independently verified.

`tk rollback` restores the latest saved **source revision only**, on the same
branch. It does not rerun either installer. It refuses changed HEAD, changed
branch, tracked edits, or changed recovery refs, and uses Git's `reset --keep`
to avoid discarding local work. Both commits remain retained for investigation.
If the CLI no longer works, use the independent Python command printed during
application; it uses the saved updater, not code from the candidate checkout.

An installer failure triggers an automatic attempt at this same source-only
rollback and preserves the installer exit status. If installer-generated or
user edits prevent restoration, the receipt and recovery command remain
available. The user must resolve those edits deliberately; the updater never
resets them away. Abruptly terminated operations may retain their receipt and lock. Before
removing a reported stale lock, verify that no updater is still running.

**Source rollback does not restore host files, packages, services, or running
sessions.** Installer backups under `~/.config/terminal-kit-backups/` may help
manual host-file recovery, but they are not a transaction covering all effects.
Shell configuration still sources the live checkout, so application is not an
atomic generation switch. Signed release promotion, isolated active generations,
complete managed-file rollback, and stronger environment/ownership checks remain
future work under issue #3. Recovery refs and receipts are retained until
explicit cleanup; there is no automatic retention policy yet.
