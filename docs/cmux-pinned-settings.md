# Review of cmux settings equal to schema defaults

The 2026-09-22 review retained all 16 settings reported by `tk cmux audit
--pinned --json`. Matching a schema default did not establish that removing a
setting would preserve the intended behavior. No live settings, templates, or
presets were changed.

The audit used the installed `~/.config/cmux/cmux.json`, terminal-kit at
`4d6290fd81829d50a9e2ca4ae08f009d4fd40989`, and the canonical cmux checkout at
`26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39`. The cited cmux files matched that
commit. These are observations of that revision, not permanent statements about
upstream defaults. The installed config can differ from the template, notably
after choosing a memory mode or sidebar preset.

## Why removing a pin can change behavior

There is a concrete schema/runtime mismatch: the [schema declares
`app.focusPaneOnFirstClick` as true][schema-focus], but both
[`PaneFirstClickFocusSettings.defaultEnabled`][runtime-focus] and the
[`AppCatalogSection` setting][catalog-focus] default to false.
[`GhosttyTerminalView.acceptsFirstMouse`][first-mouse] calls that runtime helper.
Keeping the explicit true preserves the intended first-click interaction.

Even where the defaults agree, removing a JSON setting does not necessarily
select the runtime default. cmux's [managed-settings importer][importer]
restores the backed-up value for keys no longer managed by the config. Its
[`restoreUserDefaultsBackup` implementation][restore] restores the prior
preference, or removes the stored value if no preference existed. Consequently,
removing a pin releases that explicit policy to a prior preference or runtime
fallback; it is not guaranteed to be behavior-neutral.

## Decisions

All values below matched the schema at review time. "Retain" means preserve the
existing template or preset policy; it does not mean copy a live-only value into
the template.

| Setting | Observed value | Decision and evidence |
| --- | --- | --- |
| `app.focusPaneOnFirstClick` | `true` | Retain: the runtime default is false, so this is an actual behavioral override despite the schema classification. |
| `app.newWorkspacePlacement` | `"afterCurrent"` | Retain: intentional adjacent-workspace placement introduced in [95f081c][previews]; deleting it releases that ordering preference. |
| `app.openSupportedFilesInCmux` | `true` | Retain: intentional in-app file routing from [95f081c][previews], corrected to the current boolean schema in [53731b2][file-preview]. |
| `app.openMarkdownInCmuxViewer` | `true` | Retain: the same explicit in-app preview policy in [95f081c][previews]. |
| `fileExplorer.doubleClickAction` | `"preview"` | Retain: [53731b2][file-preview] explicitly pairs file-explorer preview behavior with terminal file routing; the [runtime resolver][file-runtime] agrees today. |
| `schemaVersion` | `1` | Retain: format metadata, not an interaction preference to remove based on an equality count. |
| `shortcuts.showModifierHoldHints` | `true` | Retain: discoverability was explicitly enabled in [95f081c][previews]; the [runtime catalog][shortcut-catalog] agrees today. |
| `sidebar.hideAllDetails` | `false` | Retain in preset application: [sidebar-preset.py][sidebar-preset] explicitly clears the master hide switch so the selected details can appear. This key is absent from the base template. |
| `sidebar.showAgentActivity` | `true` | Retain: preserves agent attention in both density presets, as stated in [sidebar-preset.py][sidebar-preset], and the original [quiet appearance change][quiet]. |
| `sidebar.wrapWorkspaceTitles` | `false` | Retain: the same explicit bounded-row policy in [quiet appearance][quiet] and both [sidebar presets][sidebar-preset]. |
| `terminal.agentHibernation.enabled` | `false` | Retain: normal and balanced [memory modes][memory-modes] deliberately avoid hibernating agents, independently of the current default. |
| `terminal.agentHibernation.idleSeconds` | `5` | Retain: part of the complete [memory-mode policy][memory-modes], including modes that enable hibernation; not an isolated unused knob to delete. |
| `terminal.agentHibernation.maxLiveTerminals` | `12` | Preserve live mode output: [normal mode][memory-modes] writes 12, while the template and balanced mode intentionally use 8. Do not replace or remove the user's selected mode based on schema equality. |
| `terminal.focusTextBoxOnNewTerminals` | `false` | Retain: keeps focus in the terminal; paired with the deliberate [Ghostty-owned terminal decision][textbox]. |
| `terminal.rendererRealization.enabled` | `true` | Retain: enables the renderer-reclamation policy introduced with the [memory controls][memory-history]; its timing and warm-renderer limits are deliberately configured. |
| `terminal.showTextBoxOnNewTerminals` | `false` | Retain: [6478c6b][textbox] explicitly reverted the composer-on default to keep new terminals Ghostty-owned. |

The current [sidebar catalog][sidebar-catalog] and [terminal catalog][terminal-catalog]
confirm the corresponding defaults above, but Git history and preset behavior
establish why these settings remain explicit. A later cleanup should identify
a policy we actually want to release, then inspect the runtime fallback and
managed-preference restoration before changing the template. A lower pinned
count alone is not a success criterion.

[schema-focus]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/web/data/cmux.schema.json#L477
[runtime-focus]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Sources/App/WorkspaceRuntimeSettings.swift#L86
[catalog-focus]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/AppCatalogSection.swift#L67
[first-mouse]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Sources/GhosttyTerminalView.swift#L6072
[importer]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Sources/KeyboardShortcutSettingsFileStore.swift#L1095
[restore]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Sources/KeyboardShortcutSettingsFileStore.swift#L1286
[file-runtime]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Sources/FileExplorerDoubleClickActionSettings.swift#L32
[shortcut-catalog]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/KeyboardShortcutsCatalogSection.swift#L13
[sidebar-catalog]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/SidebarCatalogSection.swift
[terminal-catalog]: https://github.com/teamleaderleo/cmux/blob/26d5a61f7fd9bbb5f0db0f91bd4061d4a7022b39/Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/TerminalCatalogSection.swift
[previews]: https://github.com/teamleaderleo/terminal-kit/commit/95f081c545a152f5bd7f64b5073e9cc07ddbfefb
[file-preview]: https://github.com/teamleaderleo/terminal-kit/commit/53731b2fe140594a9705d8542ae9f5a5ad12a98f
[quiet]: https://github.com/teamleaderleo/terminal-kit/commit/ab8345e943e6600e33ec10afe1f7ab279243f6f9
[textbox]: https://github.com/teamleaderleo/terminal-kit/commit/6478c6b3b9db3b10cc7b974b2f73fee30c3ae375
[memory-history]: https://github.com/teamleaderleo/terminal-kit/commit/982df9bba6e2c53aca671f51997bde950cc265a5
[sidebar-preset]: https://github.com/teamleaderleo/terminal-kit/blob/4d6290fd81829d50a9e2ca4ae08f009d4fd40989/scripts/sidebar-preset.py#L21
[memory-modes]: https://github.com/teamleaderleo/terminal-kit/blob/4d6290fd81829d50a9e2ca4ae08f009d4fd40989/scripts/memory.sh#L56
