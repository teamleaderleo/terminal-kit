"""Change sidebar density without altering theme, shortcuts, or agent processes."""
import json
from pathlib import Path
import sys
from customization import atomic


def configure(home, root, name):
    presets = json.loads((root / 'config/cmux/sidebar-presets.json').read_text())
    if name not in presets:
        raise ValueError('Choose quiet or details')
    statefile = home / '.config/terminal-kit/customization/state.json'
    if statefile.exists() and json.loads(statefile.read_text())['active'] == 'off':
        raise ValueError('Turn Terminal Kit customization on before changing its sidebar preset')
    path = home / '.config/cmux/cmux.json'
    if path.is_symlink():
        raise ValueError('Refusing to replace a symlinked cmux configuration')
    config = json.loads(path.read_text()) if path.exists() else {}
    sidebar = config.setdefault('sidebar', {})
    sidebar.update(presets[name])
    # Keep attention visible in both modes; bound summaries in Details.
    sidebar.update(hideAllDetails=False, wrapWorkspaceTitles=False,
                   showAgentActivity=True, notificationMessageLineLimit=1)
    atomic(path, (json.dumps(config, indent=2) + '\n').encode())


if __name__ == '__main__':
    try:
        configure(Path.home(), Path(__file__).resolve().parents[1], sys.argv[1])
        print('Sidebar: ' + sys.argv[1] + '. cmux watches this setting; reload configuration if needed.')
    except (ValueError, OSError, TypeError, KeyError, IndexError) as error:
        sys.exit(str(error))
