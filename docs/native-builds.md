# Native cmux development

Use the single `~/Projects/cmux` checkout. `tk cmux path` shows the effective
location; `TERMINAL_KIT_CMUX_DIR` can explicitly override it. Retired
`cmux-terminal-kit` folders are no longer recreated.

`tk cmux warm` and `tk cmux build` run the checkout's `glaeda.apple.json` app
profile through `glaeda-apple`. They accept a feature branch and local edits and
do not pull, switch branches, or rerun setup. The profile owns the build tag and
Glaeda owns its persistent toolchain-specific cache. Run again after edits or a
completed pull; native incremental compilation decides what needs rebuilding.

If a build cache is quarantined after interruption, choose a new generation:

```sh
tk cmux warm --generation recovery-1
```

`build` accepts the same option. Labels are 1–64 lowercase letters, digits, or
hyphens and must start with a letter or digit. Keep using the selected label on
subsequent builds to reuse that generation. A new label starts a cold build,
which can take tens of minutes; existing caches are retained. The option cannot
be combined with `TERMINAL_KIT_CMUX_TAG`.

For a stale active-run record, Glaeda's `recover --run-id` requires the exact
interrupted run ID and an absent build process group. Recovery records the
interruption and quarantines its cache; it does not resume compilation. Follow
Glaeda's recovery instructions, then select a new generation through `tk`.

`tk cmux sync` remains an explicit fast-forward of a clean fork `main`.
`tk cmux setup` additionally prepares dependencies and the native toolchain.
Updating from upstream is a separate reviewed Git operation: sync does not merge
upstream into a divergent personal fork.

`tk cmux launch` retains the project's native build-and-launch flow with the
`terminal-kit` tag. An explicit `TERMINAL_KIT_CMUX_TAG` also makes `build` use the
native helper. These native runs use the tag's own DerivedData and preserve global
CLI links; they are separate from Glaeda's build-only cache. Do not run native
and managed builds concurrently. `warm` refuses a tag override rather than
silently building a different tag.

For build-only use, prefer warm. A successful build does not launch or replace
the production app. Native signing, launch and tag identity remain cmux's job.

## Audit installed cmux settings

Run `tk cmux audit` after an upgrade to compare the installed
`~/.config/cmux/cmux.json` with `web/data/cmux.schema.json` in the checkout
reported by `tk cmux path`. `--pinned` selects settings equal to a declared
default; `--json` emits stable JSON-pointer paths, values, defaults, counts,
and source paths. Both options can be combined. Counts always cover the entire
config, even when rows are filtered. Use `--config FILE` and `--schema FILE`
to compare another config or a saved schema without changing either file.

The report distinguishes overridden values, pinned values, declared settings
without defaults (`undeclared`), and unknown paths. It compares arrays as whole,
ordered values. Objects with explicit defaults are compared as whole values;
otherwise it walks nonempty objects and compares empty objects as values.
Parent-object defaults are not expanded into child settings. Objects accepted
through unrestricted extension points are reported as undeclared whole values,
not as unknown descendant settings. Local JSON-pointer references are resolved;
external, cyclic, conflicting, and conditional schemas are treated
conservatively and annotated. Direct defaults alongside validation alternatives
can still be compared, but defaults inside alternatives are not inferred.

This is a read-only comparison of schema annotations, not a schema validator or
a report of effective application settings. Schema defaults may differ from
runtime behavior. Pinned settings can be intentional; the command does not
remove settings, fetch schemas, build, reload, or write config. Missing or
malformed files are errors. The top-level `$schema` metadata is excluded.

JSON Schema's [`default` is an annotation](https://json-schema.org/understanding-json-schema/reference/annotations),
not an instruction to fill missing values. Do not automatically remove pinned
settings based on this report. Text output shortens long values; `--json`
preserves complete values.

The [2026-09-22 pinned-setting review](cmux-pinned-settings.md) records why all
16 observed pins were retained, including a schema/runtime default mismatch
and cmux's restoration of prior preferences when managed keys disappear.
