import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('recent', Path(__file__).with_name('recent.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
SID = '12345678-1234-1234-1234-123456789abc'

class RecentTests(unittest.TestCase):
    def test_discovery_identity_titles_and_partial_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            c = home/'.claude/projects/project'/f'{SID}.jsonl'
            c.parent.mkdir(parents=True)
            c.write_text('\n'.join(json.dumps(x) for x in [
                {'cwd':temp, 'sessionId':SID, 'type':'user'},
                {'type':'ai-title','aiTitle':'Old title'},
                {'type':'custom-title','customTitle':'My title'}])+'\n{"unfinished":')
            d=home/'.codex/sessions/day/session.jsonl';d.parent.mkdir(parents=True)
            d.write_text(json.dumps({'type':'session_meta','payload':{'id':SID,'cwd':temp}})+'\n')
            (home/'.codex/session_index.jsonl').write_text(json.dumps({'id':SID,'thread_name':'Codex title'})+'\n')
            before=c.read_bytes()
            items=r.discover(home)
            self.assertEqual(len(items),2)
            self.assertEqual({x['title'] for x in items},{'My title','Codex title'})
            self.assertEqual(c.read_bytes(),before)
            self.assertEqual(r.resume_args(next(x for x in items if x['provider']=='Claude')),['claude','--resume',SID])

    def test_launch_keeps_directory_and_quoted_command_as_data(self):
        with tempfile.TemporaryDirectory(prefix="project ' ") as cwd:
            item={'provider':'Codex','id':SID,'cwd':cwd,'title':'$(not-a-command)'}
            with patch.object(r.subprocess,'run') as run:
                r.launch(item,'/tag cli')
            args=run.call_args.args[0]
            self.assertEqual(args[0],'/tag cli')
            self.assertEqual(args[args.index('--cwd')+1],cwd)
            layout=json.loads(args[-1])
            self.assertEqual(layout['pane']['surfaces'][0]['command'],'codex resume '+SID)
            with self.assertRaises(ValueError):
                r.resume_args(dict(item,id='; bad'))

if __name__=='__main__':unittest.main()
