# cmux ricing roadmap

“Ricing” is the Unix/Linux customisation habit of making the desktop and terminal visually cohesive and personally efficient. With cmux, the useful version goes beyond wallpaper-and-colour changes: the terminal, shell, multiplexer, sidebar, project actions, browser, notifications, and workspace layouts can operate as one system.

## Implemented in terminal-kit

- Ranked cmux theme shortlist with Catppuccin Mocha as the fallback.
- Manual theme browser and setters through `terminal-kit theme`.
- Top-theme cycling, random selection, deterministic daily selection, and opt-in launchd rotation.
- Native macOS glass with an opaque-background toggle.
- cmux sidebar background matched to the active terminal theme.
- tmux status and borders based on ANSI colours so they follow theme changes.
- `bat` and Delta configured to inherit theme-responsive colours where possible.
- Mac-style Zsh selection, clipboard, undo, redo, and deletion.
- Calm command validation colours, searchable history, fuzzy selection, and directory jumping.

## How deep cmux goes

### Appearance

- Hundreds of bundled Ghostty themes and user themes.
- Separate light and dark themes.
- Fonts, font features, ligatures, cursor styles, padding, opacity, native glass, and optional shaders.
- Sidebar background, workspace washes, badges, and metadata visibility.

### Workspace UI

- Vertical workspaces, surface tabs, horizontal and vertical splits.
- Sidebar branch, pull request, directory, port, progress, agent activity, and notification details.
- Custom surface-tab buttons and plus-button menus.
- A right-side Dock for logs, test watchers, Git TUIs, servers, queues, or Feed.

### Project workflows

- Project-local `.cmux/cmux.json` files can define named workspace layouts.
- One action can open terminals, agents, browsers, worktrees, SSH sessions, and dev servers in a repeatable split layout.
- Command Palette actions can expose common workflows without memorising shell commands.

### Automation

- CLI and socket API for creating workspaces, tabs, panes, browser surfaces, and sending keystrokes.
- Browser accessibility snapshots, clicks, form filling, JavaScript evaluation, and screenshots.
- Notifications, unread navigation, Feed event sources, hooks, and agent-aware activity.
- Workspace names, descriptions, colours, loading state, and metadata can be updated programmatically.

## Remaining gaps

- The beta cmux TextBox pill radius and placeholder are app-owned and do not have appearance settings yet.
- cmux workspace accent colours are fixed hex values rather than semantic colours from the active Ghostty theme.
- True-colour application themes do not automatically share one universal theme name. Terminal ANSI, `bat`, Delta, editors, Git TUIs, and web views each have their own theme systems.
- Prompt decoration is separate from terminal theming. A minimal Starship profile could add directory, Git, duration, and status information without becoming noisy.
- Theme quality is subjective, but legibility can be tested. A future tool can render the same ANSI, syntax, diff, and log samples and flag weak contrast pairs.

## Sensible next upgrades

1. Build a restrained prompt profile with large, stable visual anchors and no powerline clutter.
2. Add a theme test command that renders ANSI colours, valid/invalid Zsh tokens, paths, code, Git diffs, and logs on one screen.
3. Create project presets: development, review, documentation, SSH, and agent-worktree layouts.
4. Add a Dock with lazygit, test output, a development server, and cmux Feed.
5. Add per-theme companion mappings only where ANSI adaptation is insufficient.
6. Consider a subtle cursor-location shader only after measuring readability and power use; avoid animated bloom, scanlines, and chromatic effects for long sessions.
