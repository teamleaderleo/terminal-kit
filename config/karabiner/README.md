# Karabiner configuration

`karabiner.json` is the operator's full Karabiner-Elements configuration snapshot. It is intentionally kept in Git so a fresh Mac can recover the same keyboard behavior without reconstructing device mappings and complex rules by hand.

`terminal-kit.json` is separate: it contains only terminal-kit's cmux-scoped additive rule. Installing terminal-kit may merge that owned rule into the live Karabiner profile, but it must preserve the rest of the operator's configuration.

## Maintenance

When the operator intentionally changes Karabiner settings, refresh `karabiner.json` from `~/.config/karabiner/karabiner.json` in the same reviewed terminal-kit change when practical. Treat the checked-in full snapshot as a backup/recovery artifact, not as permission to overwrite a live machine automatically.

Before restoring the snapshot onto a Mac, back up that Mac's existing `~/.config/karabiner/karabiner.json`. The snapshot includes device identifiers, per-device simple modifications, complex modifications, selected-profile state, and virtual keyboard settings.

The existing `tk karabiner export`/portable-snapshot path serves a different purpose: selective cross-machine merging. It intentionally omits device-specific state. Do not substitute it for this full backup when exact recovery is the goal.
