import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('customization', ROOT / 'scripts/customization.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Profiles(unittest.TestCase):
    def test_round_trip_and_independent_edits(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            path = home / m.FILES[0]
            path.parent.mkdir(parents=True)
            preset = json.loads((ROOT / 'config/cmux/cmux.json.example').read_text())
            preset['unrelated'] = {'keep': True}
            path.write_text(json.dumps(preset))
            ghostty = home / m.FILES[2]
            ghostty.parent.mkdir(parents=True)
            ghostty.write_text('font-size = 15\n# >>> terminal-kit: ghostty >>>\nconfig-file = "kit"\n# <<< terminal-kit: ghostty <<<\n')
            original = m.capture(home)
            self.assertEqual(m.switch(home, ROOT, 'off'), 'off')
            self.assertEqual(json.loads(path.read_text()), {'unrelated': {'keep': True}})
            self.assertEqual(ghostty.read_text(), 'font-size = 15\n')
            ghostty.write_text('font-size = 17\n')
            self.assertEqual(m.switch(home, ROOT, 'on'), 'on')
            self.assertEqual(m.capture(home), original)
            m.switch(home, ROOT, 'toggle')
            self.assertEqual(ghostty.read_text(), 'font-size = 17\n')
            before = m.capture(home)
            m.switch(home, ROOT, 'off')
            self.assertEqual(m.capture(home), before)

    def test_malformed_input_changes_nothing(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            p = home / m.FILES[0]
            p.parent.mkdir(parents=True)
            p.write_text('{bad')
            before = m.capture(home)
            with self.assertRaises(ValueError):
                m.switch(home, ROOT, 'off')
            self.assertEqual(m.capture(home), before)

    def test_recovery(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            m.switch(home, ROOT, 'off')
            before = m.capture(home)
            directory = home / '.config/terminal-kit/customization'
            state = json.loads((directory / 'state.json').read_text())
            (directory / 'pending.json').write_text(json.dumps({'before': before, 'state': state}))
            (home / m.FILES[0]).parent.mkdir(parents=True, exist_ok=True)
            (home / m.FILES[0]).write_text('partial write')
            self.assertEqual(m.switch(home, ROOT, 'status'), 'off')
            self.assertEqual(m.capture(home), before)

    def test_customized_values_survive(self):
        self.assertEqual(m.subtract({'x': 2, 'y': 3}, {'x': 1, 'y': 3}), {'x': 2})


unittest.main()
