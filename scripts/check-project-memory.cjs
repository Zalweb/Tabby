#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const args = process.argv.slice(2);
const option = name => { const i=args.indexOf(name); return i<0 ? null : args[i+1]; };
const root = path.resolve(option('--root') || path.join(__dirname,'..'));
const read = p => fs.readFileSync(path.join(root,p),'utf8').replace(/\r\n/g,'\n');
const exists = p => fs.existsSync(path.join(root,p));
const errors=[];
const fail = s => errors.push(s);
function walk(dir) {
 if(!exists(dir)) return [];
 return fs.readdirSync(path.join(root,dir),{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(`${dir}/${e.name}`):[`${dir}/${e.name}`]);
}
function metadata(p,kind) {
 try { const match=read(p).match(new RegExp('```json '+kind+'-metadata\\n([\\s\\S]*?)\\n```')); if(!match) throw Error('missing metadata block'); return JSON.parse(match[1]); }
 catch(e) {fail(`${p}: ${e.message}`);return null;}
}
const taskFiles=walk('docs/progress/tasks').filter(p=>p.endsWith('.md'));
const tasks=taskFiles.map(file=>({file,m:metadata(file,'task')})).filter(t=>t.m);
if(!tasks.length) fail('No task records found');
const byId=new Map();
const states=['planned','ready','in_progress','implemented','verified','complete','blocked','deferred'];
const required=['id','area','title','milestone','priority','status','owner','platform','branch','base_commit','updated_at','audit_ids','dependencies','read_set','coverage','verification','required_checks'];
const sections=['Scope and acceptance','Implemented','Remaining and unverified','Verification results','Deployment','Handoff','History'];
for(const {file,m} of tasks) {
 for(const key of required) if(!(key in m)) fail(`${file}: missing ${key}`);
 if(byId.has(m.id)) fail(`Duplicate task ID ${m.id}`); byId.set(m.id,{file,m});
 if(path.basename(file)!==`${m.id}.md`) fail(`${file}: filename must match task ID`);
 if(!states.includes(m.status)) fail(`${file}: invalid status ${m.status}`);
 if(!['M0','M1','M2','M3'].includes(m.milestone)) fail(`${file}: invalid milestone`);
 if(!['P1','P2','P3'].includes(m.priority)) fail(`${file}: invalid priority`);
 if(typeof m.updated_at!=='string'||!/(Z|[+-]\d\d:\d\d)$/.test(m.updated_at)||Number.isNaN(Date.parse(m.updated_at))) fail(`${file}: timestamp needs ISO timezone`);
 for(const key of ['audit_ids','dependencies','read_set','coverage','verification','required_checks']) if(!Array.isArray(m[key])) fail(`${file}: ${key} must be an array`);
 for(const p of m.read_set||[]) if(!exists(p)) fail(`${file}: missing read-set path ${p}`);
 for(const s of sections) { const re=new RegExp('^## '+s+'\\n\\n([^]*?)(?=\\n## |$)','m'); const content=read(file).match(re); if(!content||!content[1].trim()) fail(`${file}: missing content for ${s}`); }
 if(['in_progress','implemented','verified','complete'].includes(m.status)) {
   if(!m.owner||m.owner==='unassigned'||!m.platform||m.platform==='unassigned'||!m.branch||!m.base_commit) fail(`${file}: active/finished task requires owner/platform/branch/base_commit`);
 }
 if(['blocked','deferred'].includes(m.status)&&!m.blocker) fail(`${file}: ${m.status} needs blocker/reason metadata`);
 for(const p of m.coverage||[]) if(path.isAbsolute(p)||p.includes('\\')||p.includes('..')) fail(`${file}: coverage must be repository-relative`);
}
const visited=new Set(), visiting=new Set();
function visit(id) { if(visiting.has(id)){fail(`Dependency cycle at ${id}`);return;} if(visited.has(id))return; visiting.add(id); const t=byId.get(id); for(const d of t?.m.dependencies||[]){if(!byId.has(d))fail(`${id}: unknown dependency ${d}`);else visit(d);} visiting.delete(id);visited.add(id); }
for(const {m} of tasks) visit(m.id);
const evidence=new Map();
for(const file of walk('docs/verification').filter(p=>p.endsWith('.md')&&!p.endsWith('/README.md'))) {
 const m=metadata(file,'verification'); if(!m)continue;
 if(evidence.has(m.id))fail(`Duplicate verification ID ${m.id}`); evidence.set(m.id,{file,m});
 for(const k of ['id','task_ids','checks','timestamp','tested_commit','dirty_tree','environment','commands']) if(!(k in m))fail(`${file}: missing ${k}`);
 for(const s of ['Expected and actual results','Evidence','Limits and next action']) if(!read(file).includes('## '+s+'\n'))fail(`${file}: missing evidence section ${s}`);
 if(!m.environment||!m.tested_commit||!m.timestamp||Number.isNaN(Date.parse(m.timestamp)))fail(`${file}: incomplete evidence environment/commit/timestamp`);
 if(typeof m.dirty_tree!=='boolean')fail(`${file}: dirty_tree must be boolean`);
 if(!Array.isArray(m.task_ids)||!Array.isArray(m.checks)||!Array.isArray(m.commands))fail(`${file}: task_ids/checks/commands must be arrays`);
 for(const id of m.task_ids||[])if(!byId.has(id))fail(`${file}: unknown task ${id}`);
 for(const c of m.checks||[])if(!c.category||!['passed','failed','unverified'].includes(c.outcome))fail(`${file}: invalid check`);
}
for(const {file,m} of tasks) {
 const passed=new Set();
 const latestChecks=new Map();
 for(const id of m.verification||[]) {const e=evidence.get(id);if(!e){fail(`${file}: unknown verification ${id}`);continue;} if(!e.m.task_ids?.includes(m.id))fail(`${file}: evidence ${id} does not name task`); for(const c of e.m.checks||[]){const previous=latestChecks.get(c.category);if(!previous||Date.parse(e.m.timestamp)>=previous.time)latestChecks.set(c.category,{outcome:c.outcome,time:Date.parse(e.m.timestamp)});}}
 for(const [category,check] of latestChecks)if(check.outcome==='passed')passed.add(category);
 if(['verified','complete'].includes(m.status)) {
  if(m.acceptance_review?.pending_checks?.length)fail(`${file}: acceptance review has open checks: ${m.acceptance_review.pending_checks.join(', ')}`);
  if(!m.required_checks?.length)fail(`${file}: completed work needs required checks`);
  for(const c of m.required_checks||[])if(!passed.has(c))fail(`${file}: no passed evidence for ${c}`);
  for(const d of m.dependencies||[])if(byId.get(d)?.m.status!=='complete')fail(`${file}: dependency ${d} incomplete`);
 }
 if(m.status==='ready')for(const d of m.dependencies||[])if(byId.get(d)?.m.status!=='complete')fail(`${file}: ready dependency ${d} incomplete`);
}
const auditPath='docs/audits/2026-10-31-android-review.md';
const auditIds=exists(auditPath)?[...read(auditPath).matchAll(/^## (AUD-\d{8}-\d+)$/gm)].map(x=>x[1]):[];
if(!auditIds.length)fail('Audit register missing or empty');
if(new Set(auditIds).size!==auditIds.length)fail('Duplicate audit IDs');
for(const id of auditIds)if(!tasks.some(t=>t.m.audit_ids?.includes(id)))fail(`Unmapped audit ${id}`);
for(const {m} of tasks)for(const id of m.audit_ids||[])if(!auditIds.includes(id))fail(`${m.id}: unknown audit ID ${id}`);
const activeFiles=['AGENTS.md','README.md',...walk('docs').filter(p=>p.endsWith('.md')&&!p.startsWith('docs/archive/'))].filter(p=>exists(p)&&!read(p).startsWith('> HISTORICAL RECORD:'));
for(const file of activeFiles) {
 const content=read(file).replace(/```[^]*?```/g,'');
 for(const match of content.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
  const target=match[1]; if(/^(https?:|mailto:|#)/.test(target))continue;
  const [pathname,anchor]=target.split('#'); const resolved=path.resolve(root,path.dirname(file),decodeURIComponent(pathname));
  if(!resolved.startsWith(root+path.sep)&&resolved!==root){fail(`${file}: link escapes repository ${target}`);continue;}
  if(!fs.existsSync(resolved)){fail(`${file}: broken link ${target}`);continue;}
  if(anchor&&resolved.endsWith('.md')) {
   const headings=fs.readFileSync(resolved,'utf8').split('\n').filter(l=>/^#{1,6} /.test(l)).map(l=>l.replace(/^#+ /,'').trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu,'').replace(/\s/g,'-'));
   if(!headings.includes(anchor))fail(`${file}: unknown anchor ${target}`);
  }
 }
 if(/(?:all|every) (?:project )?documentation (?:must|shall) (?:be|remain|live).*AGENTS\.md/i.test(content))fail(`${file}: superseded single-document mandate`);
}
function statusText() {
 const sorted=[...tasks].sort((a,b)=>a.m.id.localeCompare(b.m.id));
 const counts=['M0','M1','M2','M3'].map(m=>{
  const ts=tasks.filter(t=>t.m.milestone===m), total=ts.length;
  const count=states=>ts.filter(t=>states.includes(t.m.status)).length;
  return `| ${m} | ${count(['implemented','verified','complete'])} / ${total} | ${count(['verified','complete'])} / ${total} | ${count(['complete'])} / ${total} |`;
 });
 const m1=tasks.filter(t=>t.m.milestone==='M1');
 const reviewed=m1.filter(t=>t.m.acceptance_review?.local_review==='passed').length;
 const open=new Map();
 for(const {m} of m1.filter(t=>t.m.status!=='complete')) {
  for(const gate of m.acceptance_review?.pending_checks||m.required_checks.filter(c=>c!=='regression')) open.set(gate,(open.get(gate)||0)+1);
 }
 return '# Current project progress\n\nGenerated from task metadata by `node scripts/check-project-memory.cjs --write`. Do not edit this projection manually. Ownership, evidence and handoff details live in task records.\n\n## Milestones\n\n| Milestone | Implemented or later / total | Verified or complete / total | Complete / total |\n|---|---|---|---|\n'+counts.join('\n')+
 '\n\nImplementation coverage counts source work; complete additionally requires every acceptance, review and integration gate. Local fixtures never establish live backend or real-device acceptance.\n\n## M1 acceptance review\n\nLocal review recorded for '+reviewed+' / '+m1.length+' tasks. Open checks below remain unverified until their required environment is actually tested.\n\n| Open check | Incomplete tasks requiring it |\n|---|---|\n'+[...open].sort().map(([gate,n])=>'| '+gate+' | '+n+' |').join('\n')+
 '\n\nM3 candidate/device/deployment verification remains a release gate even before a candidate task is claimed. No remediation is inferred from a baseline test count.\n\n## Tasks, owners and next actions\n\n| Task | Milestone | Priority | State | Owner | Dependencies / next action |\n|---|---|---|---|---|---|\n'+sorted.map(({m})=>`| [${m.id}](tasks/${m.id}.md) � ${m.title} | ${m.milestone} | ${m.priority} | ${m.status} | ${m.owner} | ${(m.dependencies||[]).join(', ')||'none'}; ${m.status==='ready'?'claim and reproduce':m.status==='complete'?'see verification':m.status==='blocked'?'resolve recorded blocker':'read task handoff'} |`).join('\n')+
 '\n\n## Open release gates\n\n- M1 implementation exists; tasks stay open until required acceptance and review evidence passes.\n- Required backend/device checks cannot be closed by source inspection or mocks.\n- Exact signed artifact, upgrade compatibility, applied migrations and authorization required before publishing.\n- M2 capabilities remain hidden until verified; development does not waive incomplete M1 dependencies.\n';
}

const generated=statusText();
if(args.includes('--write')) {fs.mkdirSync(path.join(root,'docs/progress'),{recursive:true});fs.writeFileSync(path.join(root,'docs/progress/STATUS.md'),generated);}
else if(!exists('docs/progress/STATUS.md')||read('docs/progress/STATUS.md')!==generated)fail('Status projection stale; run with --write');
const base=option('--base');
if(base) {
 try {
  const git=(argv)=>cp.execFileSync('git',argv,{cwd:root,encoding:'utf8'}).trim().split('\n').filter(Boolean);
  const changed=[...new Set([...git(['diff','--name-only',base,'--']),...git(['ls-files','--others','--exclude-standard'])])];
  const updated=tasks.filter(t=>changed.includes(t.file));
  if(changed.length&&!updated.length)fail('Changes require an updated task record');
  const glob=(p,g)=>{const escape=s=>s.replace(/[.+?^${}()|[\]\\]/g,'\\$&');return new RegExp('^'+g.split('**').map(s=>s.split('*').map(escape).join('[^/]*')).join('.*')+'$').test(p);};
  for(const p of changed) {
   if(p.startsWith('docs/progress/tasks/'))continue;
   if(!updated.some(t=>(t.m.coverage||[]).some(g=>glob(p,g))))fail(`Changed file lacks coverage in an updated task: ${p}`);
  }
 } catch(e){fail(`Cannot inspect change base: ${e.message}`);}
}
if(errors.length){for(const e of errors)console.error('ERROR: '+e);process.exitCode=1;}
else console.log(`Project memory valid: ${tasks.length} tasks, ${auditIds.length} audit findings, ${evidence.size} verification records.`);
