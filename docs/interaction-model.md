# Familiar interaction model

terminal-kit should make cmux feel like a browser and Finder where those conventions transfer cleanly, while preserving normal terminal selection and editing.

## Existing familiar controls

- `Cmd-T` opens a new terminal surface.
- `Cmd-W` closes the current surface/tab.
- `Cmd-Shift-T` reopens the last closed surface/workspace.
- `Ctrl-Tab` / `Ctrl-Shift-Tab` move between surfaces.
- `Cmd-Shift-]` / `Cmd-Shift-[` are accepted as browser-style next/previous-tab aliases on macOS.
- `Cmd-C`, `Cmd-V`, and `Cmd-A` keep their ordinary editing/clipboard roles at the shell prompt.
- Right-click opens a context menu. Selection still copies automatically.
- The cmux Files sidebar is the pointer-first file browser; its double-click action is preview.

## Pointer direction

Plain click and drag remain safe for terminal cursor placement and text selection. Raw terminal double-click remains word selection unless cmux can prove the pointer is over a resolvable filesystem entry without breaking selection semantics.

The desired future behavior for a proven terminal path is:

- double-click a directory: enter it in the current shell;
- double-click a supported file: preview it in cmux;
- middle-click a proven path: open it in a new surface when that can be implemented without stealing middle-click paste from ordinary terminal use;
- right-click a proven path: show familiar Open / Preview / Copy Path / Reveal in Finder actions.

This should build on cmux/Ghostty path resolution instead of parsing arbitrary terminal text in shell aliases.
