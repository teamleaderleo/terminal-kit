#!/usr/bin/env python3
"""Read-only local conversation discovery; resume only after explicit selection."""
import argparse
import curses
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time
import uuid
from recent_organization import Organization, arrange, codex_rows, identity

UUID = re.compile(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')


def clean(value):
    return ' '.join(''.join(c for c in str(value or '') if c.isprintable() or c.isspace()).split())[:180]


def records(path, size=131072):
    """Bound transcript I/O; skip partial/concurrently written records."""
    try:
        with path.open('rb') as f:
            head = f.read(size)
            f.seek(0, 2)
            length = f.tell()
            chunks = [head]
            if length > size:
                f.seek(max(size, length-size))
                chunks.append(f.read(size).split(b'\n', 1)[-1])
        for chunk in chunks:
            for line in chunk.splitlines():
                try:
                    value = json.loads(line)
                    if isinstance(value, dict):
                        yield value
                except (ValueError, UnicodeDecodeError):
                    pass
    except OSError:
        return


def newest(paths, limit):
    found = []
    for path in paths:
        try:
            if not path.is_symlink():
                found.append((path.stat().st_mtime, path))
        except OSError:
            pass
    return sorted(found, reverse=True)[:limit]


def discover(home=None, limit=200):
    home = Path(home or Path.home())
    codex = Path(os.environ.get('CODEX_HOME', home/'.codex')) if home == Path.home() else home/'.codex'
    claude = Path(os.environ.get('CLAUDE_CONFIG_DIR', home/'.claude')) if home == Path.home() else home/'.claude'
    titles = {}
    # Index is metadata-only. Later entries replace earlier titles.
    try:
        with (codex/'session_index.jsonl').open() as f:
            for line in f:
                try:
                    item = json.loads(line)
                    titles[item['id']] = clean(item.get('thread_name'))
                except (ValueError, KeyError, TypeError):
                    pass
    except OSError:
        pass
    indexed = codex_rows(codex, limit)
    result = indexed or []
    for item in result:
        item['title'] = titles.get(item['id']) or clean(item['title']) or 'Untitled conversation'
    for provider, candidates in [('Claude', claude.glob('projects/*/*.jsonl')), ('Codex', codex.glob('sessions/**/*.jsonl'))]:
        if provider == "Codex" and indexed is not None:
            continue
        for modified, path in newest(candidates, limit):
            sid = path.stem if provider == 'Claude' else None
            cwd = title = custom = ''
            for record in records(path):
                if provider == 'Codex':
                    if record.get('type') == 'session_meta':
                        payload = record.get('payload', {})
                        sid = payload.get('id') or payload.get('session_id')
                        cwd = payload.get('cwd', '')
                    continue
                if not record.get('isSidechain'):
                    cwd = cwd or record.get('cwd', '')
                if record.get('type') == 'custom-title':
                    custom = clean(record.get('customTitle'))
                elif record.get('type') == 'ai-title':
                    title = clean(record.get('aiTitle'))
            if not isinstance(sid, str) or not UUID.fullmatch(sid) or not isinstance(cwd, str) or not Path(cwd).is_absolute():
                continue
            result.append(dict(provider=provider, id=sid, cwd=cwd,
                               title=(custom or title if provider == 'Claude' else titles.get(sid)) or 'Untitled conversation',
                               updated=modified))
    # Stable provider+ID identity, never combine different providers' conversations.
    unique = {}
    for item in sorted(result, key=lambda x: x['updated'], reverse=True):
        unique.setdefault((item['provider'], item['id']), item)
    # Keep provider pins even when recent unpinned work fills the cap.
    values = list(unique.values())
    return [x for x in values if x.get('source_pinned')] + [x for x in values if not x.get('source_pinned')][:limit]


def resume_args(item):
    if not UUID.fullmatch(item['id']):
        raise ValueError('Invalid session identity')
    if item['provider'] == 'Claude':
        return ['claude', '--resume', item['id']]
    if item['provider'] == 'Codex':
        return ['codex', 'resume', item['id']]
    raise ValueError('Unsupported provider')


def launch(item, cmux):
    if not Path(item['cwd']).is_dir():
        raise ValueError('Project directory is unavailable; restore it before resuming.')
    layout = {'pane': {'surfaces': [{'type': 'terminal', 'command': shlex.join(resume_args(item))}]}}
    subprocess.run([cmux, 'new-workspace', '--name', item['title'], '--cwd', item['cwd'],
                    '--focus', 'true', '--layout', json.dumps(layout)], check=True, capture_output=True)


def picker(screen, cmux):
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    screen.timeout(15000)
    items = discover()
    organization = Organization()
    recent = False
    focus_key = None
    query, selected, notice = '', 0, ''
    while True:
        ordered = arrange(items, organization.read(), recent)
        rows = [x for x in ordered if query.casefold() in (x['title']+' '+x['cwd']+' '+x['provider']+' '+x['group']).casefold()]
        if focus_key is not None:
            selected = next((i for i,x in enumerate(rows) if identity(x) == focus_key), selected)
            focus_key = None
        selected = min(selected, max(0, len(rows)-1))
        screen.erase()
        height, width = screen.getmaxyx()
        def line(y, text, attr=0):
            if y < height-1:
                try:
                    screen.addnstr(y, 0, text, max(0, width-1), attr)
                except curses.error:
                    pass
        line(0, ('Recent' if recent else 'Grouped')+' work   ·   Claude + Codex', curses.A_BOLD)
        line(1, 'Search · ↑↓ select · Enter resume · ^P pin · ^G group · ^O view · ^U inherit pin · Esc close')
        line(2, 'Search: '+query)
        capacity = max(1, (height-7)//2)
        start = max(0, selected-capacity+1)
        for n, item in enumerate(rows[start:start+capacity], start):
            y = 4+(n-start)*2
            line(y, f"{'*' if item['pinned'] else ' '} {item['provider']:6}  {item['title']}", curses.A_REVERSE if n == selected else 0)
            line(y+1, '          '+item['group'].replace(str(Path.home()), '~', 1), curses.A_DIM)
        line(height-3, notice or f'{len(rows)} conversations · local history · activity elsewhere is unknown')
        line(height-2, 'Resume opens a client; it does not move or stop an existing desktop session.', curses.A_DIM)
        screen.refresh()
        try:
            key = screen.get_wch()
        except curses.error:
            previous = (rows[selected]['provider'], rows[selected]['id']) if rows else None
            items = discover()
            refreshed = [x for x in arrange(items, organization.read(), recent) if query.casefold() in (x['title']+' '+x['cwd']+' '+x['provider']+' '+x['group']).casefold()]
            selected = next((i for i, x in enumerate(refreshed) if (x['provider'], x['id']) == previous), 0)
            continue
        if key == '\x1b':
            return
        if key == curses.KEY_UP:
            selected = max(0, selected-1)
        elif key == curses.KEY_DOWN:
            selected = min(len(rows)-1, selected+1)
        elif key == '\x0f':
            recent = not recent
            selected = 0
        elif key in ('\x10','\x15') and rows:
            item = rows[selected]
            focus_key = identity(item)
            organization.change(identity(item),'pinned',None if key == '\x15' else not item['pinned'])
            notice = 'Workbench pin updated; source app unchanged.'
        elif key == '\x07' and rows:
            screen.timeout(-1)
            curses.echo()
            curses.curs_set(1)
            try:
                screen.move(height-3,0)
                screen.clrtoeol()
                screen.addnstr(height-3,0,'Group name (blank restores source): ',max(0,width-1))
                name = clean(screen.getstr(120).decode('utf-8',errors='replace'))
                focus_key = identity(rows[selected])
                organization.change(focus_key,'group',name or None)
                notice = 'Workbench group saved; source app unchanged.'
            finally:
                curses.noecho()
                curses.curs_set(0)
                screen.timeout(15000)
        elif key == '\x12':
            items = discover()
            notice = 'Refreshed from original histories.'
        elif key in ('\n', '\r') and rows:
            try:
                launch(rows[selected], cmux)
                notice = 'Opened '+rows[selected]['provider']+' conversation.'
            except (OSError, ValueError, subprocess.CalledProcessError) as exc:
                notice = clean(str(exc))
        elif key in ('\x7f', '\b', curses.KEY_BACKSPACE):
            query = query[:-1]
            selected = 0
        elif isinstance(key, str) and key.isprintable():
            query += key
            selected = 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true', help='Print recent conversation metadata without launching clients')
    parser.add_argument('--cmux', default='cmux', help='cmux executable (use the tagged build wrapper for dev work)')
    parser.add_argument('--sidebar', action='store_true', help='Refresh and select the native Work sidebar')
    args = parser.parse_args()
    if args.sidebar:
        rows = arrange(discover(), Organization().read())
        for item in rows:
            item['command'] = shlex.join(resume_args(item))
            item['operation'] = str(uuid.uuid4())
        template = Path(__file__).resolve().parent.parent/'config/cmux/work-history.js'
        destination = Path.home()/'.config/cmux/sidebars/tk-work.js'
        destination.parent.mkdir(parents=True, exist_ok=True)
        source = template.read_text().replace('__HISTORY__', json.dumps(rows, ensure_ascii=True))
        import tempfile
        fd, temporary = tempfile.mkstemp(dir=destination.parent, prefix='.tk-work-')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(source)
            os.replace(temporary, destination)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        subprocess.run([args.cmux, 'sidebar', 'validate', 'tk-work'], check=True)
        subprocess.run([args.cmux, 'sidebar', 'select', 'tk-work'], check=True)
    elif args.json:
        print(json.dumps(arrange(discover(), Organization().read()), ensure_ascii=False, indent=2))
    else:
        curses.wrapper(picker, args.cmux)


if __name__ == '__main__':
    main()
