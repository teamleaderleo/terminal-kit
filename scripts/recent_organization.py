"""Provider metadata reads and private, atomic workbench organization."""
import fcntl
import json
import os
from pathlib import Path
import sqlite3
import tempfile


def identity(item):
    return item['provider'] + ':' + item['id']


def codex_rows(root, limit):
    """Use the installed app's explicit assignments, never infer project membership."""
    db = root / 'state_5.sqlite'
    if not db.exists():
        return None
    try:
        try:
            desktop = json.loads((root/'.codex-global-state.json').read_text())
        except (OSError, ValueError):
            desktop = {}
        pins = desktop.get('electron-persisted-atom-state',{}).get('app-server-pinned-thread-order-v1', desktop.get('pinned-thread-ids',[]))
        pin_order = {sid:n for n,sid in enumerate(pins)}
        connection = sqlite3.connect(db.as_uri()+'?mode=ro', uri=True, timeout=0.2)
        connection.row_factory = sqlite3.Row
        with connection:
            projects = {x['id']: dict(x) for x in connection.execute('SELECT id,name,position FROM projects')}
            sections = {x['id']: x['name'] for x in connection.execute('SELECT id,name FROM thread_sections')}
            rows = connection.execute('''SELECT id,cwd,title,updated_at,is_pinned,thread_section_id,
                section_position,project_id FROM threads WHERE archived=0 AND source IN ('cli','vscode','unknown')
                ORDER BY is_pinned DESC,updated_at DESC''').fetchall()
        result = []
        for row in rows:
            project = projects.get(row['project_id'])
            if project is None:
                assignment = desktop.get('thread-project-assignments',{}).get(row['id'],{})
                pid = assignment.get('projectId')
                legacy = desktop.get('local-projects',{}).get(pid)
                if legacy:
                    ordering = desktop.get('project-order',[])
                    project = dict(name=legacy['name'],position=ordering.index(pid) if pid in ordering else 100000)
            section = sections.get(row['thread_section_id'])
            result.append(dict(provider='Codex',id=row['id'],cwd=row['cwd'],title=row['title'],
                updated=row['updated_at'],source_pinned=bool(row['is_pinned']) or row['id'] in pin_order,
                source_pin_order=pin_order.get(row['id'], row['section_position'] or 0),
                source_group=('Codex · '+section if section and section != 'Pinned' else
                              'Codex · '+project['name'] if project else 'Codex · Ungrouped'),
                source_group_order=project['position'] if project else 100000,
                organization_source='Codex saved desktop metadata'))
        return [x for x in result if x['source_pinned']] + [x for x in result if not x['source_pinned']][:limit]
    except (sqlite3.Error, OSError, ValueError):
        return None
    finally:
        if 'connection' in locals():
            connection.close()


class Organization:
    def __init__(self, path=None):
        self.path = Path(path or Path.home()/'.config/terminal-kit/recent-organization.json')

    def read(self):
        try:
            value = json.loads(self.path.read_text())
        except FileNotFoundError:
            return {'version':1, 'items':{}, 'order':[]}
        if not isinstance(value,dict) or value.get('version') != 1 or not isinstance(value.get('items'),dict) or not isinstance(value.get('order'),list):
            raise ValueError('Unrecognized workbench organization; original file preserved.')
        return value

    def change(self, key, field, value):
        self.path.parent.mkdir(parents=True,exist_ok=True)
        with self.path.with_suffix('.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            state = self.read()
            item = state['items'].setdefault(key,{})
            if value is None:
                item.pop(field,None)
            else:
                item[field] = value
            if key not in state['order']:
                state['order'].append(key)
            fd, name = tempfile.mkstemp(dir=self.path.parent,prefix='.recent-')
            try:
                with os.fdopen(fd,'w') as f:
                    json.dump(state,f,ensure_ascii=False)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(name,self.path)
            finally:
                if os.path.exists(name):
                    os.unlink(name)


def arrange(items, state, recent=False):
    result = []
    order = {key:n for n,key in enumerate(state['order'])}
    for original in items:
        item = dict(original)
        local = state['items'].get(identity(item),{})
        item['pinned'] = local.get('pinned',item.get('source_pinned',False))
        item['group'] = local.get('group') or item.get('source_group') or ('Folder · '+item['cwd'])
        item['group_origin'] = 'Workbench' if local.get('group') else item.get('organization_source','Recorded working folder')
        item['local_order'] = order.get(identity(item),100000)
        result.append(item)
    if recent:
        return sorted(result,key=lambda x:-x['updated'])
    return sorted(result,key=lambda x:(
        0 if x['pinned'] else 1,
        (0, '') if x['pinned'] else (x.get('source_group_order',100000) if x['group_origin'] != 'Workbench' else -1, x['group']),
        (x['local_order'] if x['local_order'] != 100000 else x.get('source_pin_order',100000)) if x['pinned'] else x['local_order'] if x['group_origin']=='Workbench' else 0,
        x['title'].casefold(), identity(x)))
