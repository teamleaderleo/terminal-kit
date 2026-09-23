# Work Strip: first native desktop trial

A small floating AppKit panel with stable Claude, Codex and Muse tabs. Clicking a tab activates the real installed app (Muse uses T3 Code); no browser replicas, terminal replacements or conversation transfer. The highlighted tab follows actual foreground-app activation.

Build with `bash tools/desktop-strip/build.sh`, then launch the resulting app from Finder. Drag its background/title area to put it along an edge. The × hides only the strip; use its ▱ menu-bar item to restore it or quit. Position is saved by AppKit. Existing target applications are never closed by the strip. It requests no screen recording or Accessibility access.

This first trial is an app switcher, not external-window embedding or a saved window group. It activates an application, not a particular conversation or window. It does not move, resize, capture, synchronize or close target windows. It does not promise placement across Spaces or displays. Multiple windows of the same app remain that app's responsibility.

Next gate: determine whether compact access is useful in actual overlapping-window work before adding exact window binding and group geometry. The current Codex automation restriction remains in force; do not use this app as an automation detour around it. The human can use the controls directly.
