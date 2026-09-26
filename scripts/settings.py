"""terminal-kit settings: one state file, one renderer.

State lives in ~/.config/terminal-kit/settings.json (only values that differ
from the defaults). `render` writes ~/.config/cmux/cmux.json from
config/cmux/cmux.json.example plus the overlay below, and writes the Ghostty
glass include. Nothing else in terminal-kit edits those files.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

GLASS = {
    'regular': ('0.90', 'macos-glass-regular', 'false'),
    'clear': ('0.92', 'macos-glass-clear', 'false'),
    'immersive': ('0.88', 'macos-glass-clear', 'true'),
    'opaque': ('1', 'false', 'false'),
}

# key: (default, allowed values or None for a number, description)
SETTINGS = {
    'scroll': (1.4, None, 'cmux scroll speed multiplier, 0.25 to 4'),
    'wrap': ('wrap', ('wrap', 'wide'), 'cmux text editor: wrap long lines or scroll sideways'),
    'prompt': ('minimal', ('minimal', 'detailed', 'off'), 'shell prompt (applies after exec zsh)'),
    'memory': ('normal', ('normal', 'lean'), 'lean frees idle renderers and hibernates idle agents'),
    'sidebar': ('quiet', ('quiet', 'details'), 'cmux sidebar density'),
    'glass': ('regular', tuple(GLASS), 'window transparency'),
}

SIDEBAR_DETAILS = {
    'showWorkspaceDescription': True,
    'showNotificationMessage': True,
    'showBranchDirectory': True,
    'showPullRequests': True,
    'showPorts': True,
    'showProgress': True,
}

MEMORY_LEAN = {
    'rendererRealization': {'enabled': True, 'idleSeconds': 5, 'maxWarmRenderers': 2},
    'agentHibernation': {'enabled': True, 'idleSeconds': 5, 'maxLiveTerminals': 4},
}


class SettingError(Exception):
    pass


def paths(home):
    state = home / '.config/terminal-kit'
    return {
        'state_dir': state,
        'settings': state / 'settings.json',
        'glass': state / 'glass.ghostty',
        'cmux': home / '.config/cmux/cmux.json',
        'backups': home / '.config/terminal-kit-backups',
    }


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name + '.')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as out:
            out.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def parse(key, raw):
    if key not in SETTINGS:
        raise SettingError(f'unknown setting: {key} (try: tk set)')
    default, allowed, _ = SETTINGS[key]
    if allowed is None:
        try:
            value = float(raw)
        except (TypeError, ValueError):
            raise SettingError(f'{key} must be a number') from None
        if not 0.25 <= value <= 4:
            raise SettingError(f'{key} must be between 0.25 and 4')
        return int(value) if value == int(value) else value
    raw = str(raw).strip().lower()
    if raw not in allowed:
        raise SettingError(f'{key} must be one of: {", ".join(allowed)}')
    return raw


def read_legacy(state_dir):
    """Values from the per-setting files used before settings.json existed."""
    found = {}

    def text(name):
        path = state_dir / name
        return path.read_text().strip() if path.is_file() else None

    legacy = {
        'scroll': text('scroll-speed'),
        'wrap': text('editor-wrap'),
        'prompt': {'on': 'minimal', 'enable': 'minimal'}.get(text('prompt'), text('prompt')),
        'memory': {'balanced': 'normal', 'ultra': 'lean'}.get(text('memory-mode'), text('memory-mode')),
    }
    glass = text('glass.ghostty')
    if glass:
        for line in glass.splitlines():
            if line.startswith('# terminal-kit glass preset:'):
                legacy['glass'] = line.split(':', 1)[1].strip()
    for key, raw in legacy.items():
        if raw is None:
            continue
        try:
            found[key] = parse(key, raw)
        except SettingError:
            continue
    return found


LEGACY_FILES = ('scroll-speed', 'editor-wrap', 'prompt', 'memory-mode', 'memory-auto',
                'memory-auto-runtime', 'navigation-cache-v1')


def load(home):
    p = paths(home)
    if not p['settings'].exists():
        values = read_legacy(p['state_dir'])
        values = {k: v for k, v in values.items() if v != SETTINGS[k][0]}
        save(home, values)
        for name in LEGACY_FILES:
            (p['state_dir'] / name).unlink(missing_ok=True)
    try:
        stored = json.loads(p['settings'].read_text())
    except (OSError, ValueError) as error:
        raise SettingError(f'cannot read {p["settings"]}: {error}') from None
    values = {}
    for key, raw in (stored if isinstance(stored, dict) else {}).items():
        try:
            values[key] = parse(key, raw)
        except SettingError:
            print(f'terminal-kit: warning: ignoring invalid saved {key}: {raw!r}', file=sys.stderr)
    return values


def save(home, values):
    atomic_write(paths(home)['settings'], json.dumps(values, indent=2, sort_keys=True) + '\n')


def effective(values):
    return {key: values.get(key, spec[0]) for key, spec in SETTINGS.items()}


def render_cmux(template, settings):
    config = json.loads(template)
    terminal = config.setdefault('terminal', {})
    terminal['scrollSpeed'] = settings['scroll']
    config.setdefault('fileEditor', {})['wordWrap'] = settings['wrap'] == 'wrap'
    if settings['memory'] == 'lean':
        for name, value in MEMORY_LEAN.items():
            terminal[name] = dict(value)
    if settings['sidebar'] == 'details':
        config.setdefault('sidebar', {}).update(SIDEBAR_DETAILS)
    return json.dumps(config, indent=2, ensure_ascii=False) + '\n'


def render_glass(settings):
    opacity, blur, cells = GLASS[settings['glass']]
    return (f'# terminal-kit glass preset: {settings["glass"]}\n'
            '# Generated by `tk set glass`; edits here are overwritten.\n'
            f'background-opacity = {opacity}\n'
            f'background-blur = {blur}\n'
            f'background-opacity-cells = {cells}\n')


def backup(home, path):
    directory = os.environ.get('BACKUP_DIR')
    target = Path(directory) if directory else paths(home)['backups'] / time.strftime('%Y%m%d-%H%M%S')
    target.mkdir(parents=True, exist_ok=True)
    name = str(path).lstrip('/').replace('/', '__')
    if not (target / name).exists():
        shutil.copy2(path, target / name)


def replace_if_changed(home, path, text):
    """Write `text` to `path` only when it differs; back up the old file first."""
    if path.is_symlink():
        raise SettingError(f'refusing to replace symlink: {path}')
    if path.exists():
        if path.read_text(encoding='utf-8', errors='replace') == text:
            return False
        backup(home, path)
    atomic_write(path, text)
    return True


def render(home, root=ROOT):
    settings = effective(load(home))
    p = paths(home)
    template = (root / 'config/cmux/cmux.json.example').read_text()
    changed = []
    if replace_if_changed(home, p['cmux'], render_cmux(template, settings)):
        changed.append('cmux')
    if replace_if_changed(home, p['glass'], render_glass(settings)):
        changed.append('glass')
    return changed


def describe(key, value):
    default, allowed, text = SETTINGS[key]
    choices = 'number' if allowed is None else '|'.join(allowed)
    marker = '' if value == default else '  (changed)'
    return f'{key:<8} {value!s:<10} {choices:<31} {text}{marker}'


def main(argv, home=None, root=ROOT):
    home = Path(home or Path.home())
    if argv and argv[0] in ('-h', '--help', 'help'):
        print('Usage: tk set                 list settings\n'
              '       tk set <key>           show one setting\n'
              '       tk set <key> <value>   change a setting\n'
              '       tk set <key> default   restore the default')
        return 0
    if argv == ['_render']:
        changed = render(home, root)
        for name in changed:
            print(f'terminal-kit: rendered {name}')
        return 0
    values = load(home)
    current = effective(values)
    if not argv:
        for key in SETTINGS:
            print(describe(key, current[key]))
        return 0
    key = argv[0]
    if key not in SETTINGS:
        raise SettingError(f'unknown setting: {key} (try: tk set)')
    if len(argv) == 1:
        print(current[key])
        return 0
    if len(argv) != 2:
        raise SettingError('usage: tk set <key> <value>')
    if argv[1] == 'default':
        values.pop(key, None)
    else:
        value = parse(key, argv[1])
        if value == SETTINGS[key][0]:
            values.pop(key, None)
        else:
            values[key] = value
    save(home, values)
    render(home, root)
    print(f'terminal-kit: {key} = {effective(values)[key]}')
    if key == 'prompt':
        print('terminal-kit: run exec zsh to see the new prompt')
    if key == 'glass':
        print('terminal-kit: quit and reopen cmux if the glass does not change')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except SettingError as error:
        print(f'terminal-kit: error: {error}', file=sys.stderr)
        sys.exit(1)
