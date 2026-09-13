// Native sidebar template; history JSON is inserted by tk recent --sidebar.
const history = __HISTORY__;
const [query, setQuery] = signal('');
const [collapsed, setCollapsed] = signal({});
const [detail, setDetail] = signal('');
const [pending, setPending] = signal({});
const [recent, setRecent] = signal(false);
const [showMore, setShowMore] = signal(false);
function key(r) { return r.provider + ':' + r.id; }
function buildLinks(workspaces) {
  const links = Object.create(null);
  const fallback = Object.create(null);
  for (const w of workspaces) {
    const panels = new Set((w.tabs || []).map(t => t.id));
    for (const a of w.agents || []) {
      const kind = String(a.kind).toLowerCase();
      const provider = kind.includes('claude') ? 'Claude' : kind.includes('codex') ? 'Codex' : null;
      if (!provider || !panels.has(a.panelId)) continue;
      const id = provider + ':' + String(a.id).toLowerCase();
      if (!links[id]) links[id] = {w, panel:a.panelId};
    }
    if (String(w.description || '').startsWith('tk-history:')) {
      const id = w.description.slice('tk-history:'.length);
      if (!fallback[id]) fallback[id] = {w,panel:null};
    }
  }
  // A known hosting agent beats an old placeholder workspace anywhere in the window.
  return {...fallback,...links};
}
const liveLinks = computed(() => buildLinks(data.workspaces() || []));
function linked(r) { return liveLinks()[r.provider + ':' + r.id.toLowerCase()] || null; }

function focus(r) {
  const target = linked(r);
  if (target) {
    cmux('workspace.select', {workspace_id: target.w.id});
    if (target.panel) cmux('surface.focus', {workspace_id: target.w.id, surface_id: target.panel});
    setDetail('');
  } else setDetail(detail() === key(r) ? '' : key(r));
}
function resume(r) {
  if (linked(r)) return focus(r);
  if (pending()[key(r)]) return;
  setPending({...pending(), [key(r)]: true});
  cmux('workspace.create', {title: r.title, working_directory: r.cwd,
    description: 'tk-history:' + key(r), initial_command: r.command,
    operation_id: r.operation, focus: true});
}
const groups = computed(() => {
  const needle = query().trim().toLowerCase();
  let rows = history.filter(r => !needle || [r.title,r.group,r.provider,r.cwd].join(' ').toLowerCase().includes(needle));
  if (recent()) rows = rows.slice().sort((a,b) => b.updated-a.updated);
  rows = rows.slice(0, showMore() ? 160 : 40);
  const out = [];
  for (const r of rows) {
    const name = recent() ? 'Recent' : r.pinned ? 'Pinned' : r.group.replace(/^Codex · /,'').replace(/^Folder · /,'');
    let group = out.find(g => g.name === name);
    if (!group) {group = {name, rows: []}; out.push(group);}
    group.rows.push(r);
  }
  return out;
});
sidebar(() => VStack({spacing: 5}, [
  HStack({spacing: 8}, [Text('Work').font(14).weight('semibold'), Spacer(),
    Button(() => recent() ? 'Groups' : 'Recent', () => setRecent(!recent()))]),
  TextField('', {placeholder:'Find a conversation',autofocus:false,onEdit:t=>setQuery(t || '')}),
  ForEach({items:groups,key:g=>g.name},g=>VStack({spacing:2},[
    HStack({spacing:5},[
      Text(() => collapsed()[g().name] ? '›' : '⌄').font(12).secondary(),
      Text(()=>g().name).font(11).weight('semibold').secondary().lineLimit(1), Spacer()
    ]).paddingVertical(6).onTap(()=>setCollapsed({...collapsed(),[g().name]:!collapsed()[g().name]})),
    ForEach({items:()=>collapsed()[g().name] && !query() ? [] : g().rows,key:key},r=>VStack({spacing:3},[
      Button(()=>r().title,()=>focus(r()),[HStack({spacing:7},[
        Text(()=>r().provider === 'Claude' ? '✳' : '◌').font(12).secondary(),
        Text(()=>r().title).font(12).lineLimit(1).truncation('tail'),Spacer(),
        Circle({size:4}).fill(()=>linked(r()) ? '#A6ADC8' : 'clear')
      ]).paddingHorizontal(7).paddingVertical(5).cornerRadius(5)
        .background(()=>{const x=linked(r());return x && x.w.selected ? '#80808025' : null;})
        .hoverBackground('#80808018')]),
      ForEach({items:()=>detail()===key(r()) && !linked(r()) ? [r()] : [],key:key},d=>VStack({spacing:5},[
        Text('Not linked in this window. It may be open in another app.').font(11).secondary().lineLimit(3),
        Text(()=>d().cwd).font(10).secondary().lineLimit(2),
        Button(()=>pending()[key(d())] ? 'Resume requested' : 'Resume in a new terminal',()=>resume(d())),
        Text('If another app owns it, close it there before continuing here.').font(10).secondary().lineLimit(3)
      ]).padding(8))
    ]))
  ])),
  Button(()=>showMore() ? 'Show fewer' : 'Show more',()=>setShowMore(!showMore())),
  Divider(),
  Text('Open workspaces').font(11).secondary(),
  ForEach({items:()=>data.workspaces() || [],key:w=>w.id},w=>
    Text(()=>w().title).font(11).lineLimit(1).secondary().paddingVertical(3)
      .onTap(()=>cmux('workspace.select',{workspace_id:w().id})))
]).padding(10));
