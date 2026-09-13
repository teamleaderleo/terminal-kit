const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const row = {provider:'Codex',id:'abc',title:'A',group:'Trials',cwd:'/tmp',command:'codex resume abc',operation:'op'};
let workspaces = [], calls = [];
const context = vm.createContext({
  signal: value => [()=>value, next=>{value=next;}], computed:f=>f,
  data:{workspaces:()=>workspaces}, sidebar:()=>{},
  cmux:(method,params)=>calls.push({method,params})
});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../config/cmux/work-history.js'),'utf8').replace('__HISTORY__',JSON.stringify([row])),context);
const run=code=>vm.runInContext(code,context);
run('focus(history[0])');
assert.equal(calls.length,0,'Unknown ownership must not launch on row click');
assert.equal(run('detail()'),'Codex:abc');
workspaces=[{id:'workspace',agents:[{id:'abc',kind:'codex',panelId:'panel'}],tabs:[{id:'panel',surfaceId:'different-id'}]}];
run('focus(history[0])');
assert.equal(calls.length,2);
assert.equal(calls[1].params.surface_id,'panel','Focus uses the hosting panel, not the different tab ID');
assert.equal(calls[0].method,'workspace.select');
workspaces=[];calls=[];
run('resume(history[0]); resume(history[0])');
assert.equal(calls.length,1,'Repeated click must not create duplicate clients');
assert.equal(calls[0].params.description,'tk-history:Codex:abc');
workspaces=[{id:'created',description:'tk-history:Codex:abc',tabs:[]}];calls=[];
run('resume(history[0])');
assert.equal(calls[0].method,'workspace.select');
assert.equal(calls[0].params.workspace_id,'created');
console.log('Native history actions passed');
