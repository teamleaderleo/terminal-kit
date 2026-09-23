"""Reversible cmux/Ghostty appearance profiles; never touches agent settings."""
import base64
import fcntl
import json
import os
from pathlib import Path
import re
import sys
import tempfile

FILES = ('.config/cmux/cmux.json', '.config/cmux/dock.json',
         '.config/ghostty/config',
         'Library/Application Support/com.mitchellh.ghostty/config')


def atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def capture(home):
    result = {}
    for name in FILES:
        path = home / name
        if path.is_symlink():
            raise ValueError(f'Refusing to replace symlink: {path}')
        result[name] = base64.b64encode(path.read_bytes()).decode() if path.exists() else None
    return result


def apply(home, profile):
    for name, value in profile.items():
        path = home / name
        if value is None:
            path.unlink(missing_ok=True)
        else:
            atomic(path, base64.b64decode(value))


def subtract(value, preset):
    # Remove only matching preset leaves. Preserve unrelated and customized keys.
    if isinstance(value, dict) and isinstance(preset, dict):
        result = dict(value)
        for key in preset.keys() & value.keys():
            remainder = subtract(value[key], preset[key])
            if remainder is None:
                result.pop(key)
            else:
                result[key] = remainder
        return result or None
    return None if value == preset else value


def initial_off(profile, root):
    result = dict(profile)
    for name, encoded in profile.items():
        if encoded is None:
            continue
        content = base64.b64decode(encoded).decode()
        if name.endswith('cmux.json'):
            preset = json.loads((root / 'config/cmux/cmux.json.example').read_text())
            content = json.dumps(subtract(json.loads(content), preset) or {}, indent=2) + '\n'
        elif name.endswith('dock.json'):
            preset = json.loads((root / 'config/cmux/dock.json.example').read_text())
            if json.loads(content) == preset:
                result[name] = None
                continue
        else:
            content = re.sub(r'(?m)^# >>> terminal-kit: ghostty >>>\n.*?^# <<< terminal-kit: ghostty <<<\n?', '', content, flags=re.S)
        result[name] = base64.b64encode(content.encode()).decode()
    return result


def switch(home, root, action):
    directory = home / '.config/terminal-kit/customization'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        statefile = directory / 'state.json'
        journal = directory / 'pending.json'
        if journal.exists():
            transaction = json.loads(journal.read_text())
            apply(home, transaction['before'])
            atomic(statefile, json.dumps(transaction['state']).encode())
            journal.unlink()
        state = json.loads(statefile.read_text()) if statefile.exists() else {'active': 'on'}
        if action == 'status':
            return state['active']
        target = ('off' if state['active'] == 'on' else 'on') if action == 'toggle' else action
        if target == state['active']:
            return target
        before = capture(home)
        if 'profiles' not in state:
            state['profiles'] = {'on': before, 'off': initial_off(before, root)}
        state['profiles'][state['active']] = before
        atomic(journal, json.dumps({'before': before, 'state': state}).encode())
        try:
            apply(home, state['profiles'][target])
            state['active'] = target
            atomic(statefile, json.dumps(state).encode())
        except BaseException:
            apply(home, before)
            raise
        journal.unlink()
        return target


if __name__ == '__main__':
    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if action not in ('on', 'off', 'toggle', 'status'):
        sys.exit('Usage: terminal-kit customization [on|off|toggle|status]')
    try:
        print('Terminal Kit customization: ' + switch(Path.home(), Path(__file__).resolve().parents[1], action))
    except (ValueError, OSError) as error:
        sys.exit(str(error))
