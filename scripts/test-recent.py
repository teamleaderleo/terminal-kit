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



# These tests also run when imported by unittest discovery.
class OrganizationTests(unittest.TestCase):
    def test_local_override_survives_source_refresh_and_can_inherit_again(self):
        from recent_organization import Organization, arrange, identity
        with tempfile.TemporaryDirectory() as tmp:
            store=Organization(Path(tmp)/'organization.json')
            a=dict(provider='Claude',id=SID,cwd=tmp,title='A',updated=1)
            b=dict(provider='Codex',id=SID,cwd=tmp,title='B',updated=2,source_pinned=True,source_group='Codex · Work')
            store.change(identity(a),'group','Weekend')
            store.change(identity(b),'group','Weekend')
            store.change(identity(b),'pinned',False)
            rows=arrange([a,b],store.read())
            self.assertEqual({x['group'] for x in rows},{'Weekend'})
            self.assertFalse(next(x for x in rows if x['provider']=='Codex')['pinned'])
            store.change(identity(b),'pinned',None)
            self.assertTrue(arrange([a,b],store.read())[0]['pinned'])
            self.assertEqual(Organization(store.path).read(),store.read())
            self.assertEqual(store.path.stat().st_mode & 0o777,0o600)

    def test_corrupt_overlay_is_preserved(self):
        from recent_organization import Organization
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'organization.json';path.write_text('broken')
            with self.assertRaises(ValueError):
                Organization(path).change('Claude:'+SID,'group','Work')
            self.assertEqual(path.read_text(),'broken')



class CodexOrganizationTests(unittest.TestCase):
    def test_saved_pins_and_explicit_assignment_with_empty_db_membership(self):
        import sqlite3
        from recent_organization import codex_rows
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            c=sqlite3.connect(root/'state_5.sqlite')
            c.executescript("""CREATE TABLE projects(id,name,position);
                CREATE TABLE thread_sections(id,name);
                CREATE TABLE threads(id,cwd,title,updated_at,is_pinned,thread_section_id,section_position,project_id,archived,source);
                """)
            c.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?,?)',(SID,temp,'Title',1,0,None,0,None,0,'vscode'))
            c.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?,?)',('subagent',temp,'Noise',2,0,None,0,None,0,'exec'))
            c.commit();c.close()
            (root/'.codex-global-state.json').write_text(json.dumps({
                'pinned-thread-ids':[SID], 'thread-project-assignments':{SID:{'projectId':'p'}},
                'local-projects':{'p':{'name':'Actual project'}},'project-order':['p']}))
            rows=codex_rows(root,1)
            self.assertEqual(len(rows),1)
            self.assertTrue(rows[0]['source_pinned'])
            self.assertEqual(rows[0]['source_group'],'Codex · Actual project')

if __name__=='__main__':unittest.main()
