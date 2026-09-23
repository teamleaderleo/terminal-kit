import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('preset', ROOT / 'scripts/sidebar-preset.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Presets(unittest.TestCase):
    def test_preserves_other_preferences_and_attention(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            path = home / '.config/cmux/cmux.json'
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({'terminal': {'scrollSpeed': 1.4}, 'sidebar': {'watchGitStatus': False}, 'workspaceColors': {'selectionColor': '#313244'}}))
            for name in ('quiet', 'details', 'quiet'):
                m.configure(home, ROOT, name)
                c = json.loads(path.read_text())
                self.assertEqual(c['terminal'], {'scrollSpeed': 1.4})
                self.assertEqual(c['workspaceColors']['selectionColor'], '#313244')
                self.assertFalse(c['sidebar']['watchGitStatus'])
                self.assertTrue(c['sidebar']['showAgentActivity'])
                self.assertEqual(c['sidebar']['showCustomMetadata'], name == 'details')
                self.assertEqual(c['sidebar']['notificationMessageLineLimit'], 1)
    def test_off_and_invalid_config_are_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            path = home / '.config/cmux/cmux.json'
            path.parent.mkdir(parents=True)
            path.write_text('invalid')
            with self.assertRaises(ValueError): m.configure(home, ROOT, 'quiet')
            self.assertEqual(path.read_text(), 'invalid')
            state = home / '.config/terminal-kit/customization/state.json'
            state.parent.mkdir(parents=True)
            state.write_text('{"active":"off"}')
            with self.assertRaises(ValueError): m.configure(home, ROOT, 'details')
            self.assertEqual(path.read_text(), 'invalid')

if __name__ == '__main__': unittest.main()
