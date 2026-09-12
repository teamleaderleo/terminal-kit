# Native cmux development

Use the single `~/Projects/cmux` checkout. `tk cmux path` shows the effective
location; `TERMINAL_KIT_CMUX_DIR` can explicitly override it. Retired
`cmux-terminal-kit` folders are no longer recreated.

`tk cmux warm` and `tk cmux build` run the checkout's `glaeda.apple.json` app
profile through `glaeda-apple`. They accept a feature branch and local edits and
do not pull, switch branches, or rerun setup. The profile owns the build tag and
Glaeda owns its persistent toolchain-specific cache. Run again after edits or a
completed pull; native incremental compilation decides what needs rebuilding.

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
