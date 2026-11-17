const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawnSync,execFileSync}=require('node:child_process');
const checker=path.join(__dirname,'check-project-memory.cjs');
function fixture(fn) {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'tabby-memory-'));
 const put=(p,s)=>{fs.mkdirSync(path.dirname(path.join(root,p)),{recursive:true});fs.writeFileSync(path.join(root,p),s);};
 const task={id:'DOC-001',area:'documentation',title:'Fixture',milestone:'M0',priority:'P1',status:'planned',owner:'unassigned',platform:'unassigned',branch:null,base_commit:'abc',updated_at:'2026-10-31T12:00:00+08:00',audit_ids:['AUD-20261031-001'],dependencies:[],read_set:['AGENTS.md'],coverage:['AGENTS.md','docs/**'],verification:[],required_checks:['documentation']};
 const save=()=>put('docs/progress/tasks/DOC-001.md','# Fixture\n\n```json task-metadata\n'+JSON.stringify(task)+'\n```\n\n'+['Scope and acceptance','Implemented','Remaining and unverified','Verification results','Deployment','Handoff','History'].map(s=>'## '+s+'\n\nExplicit fixture state.\n').join('\n'));
 put('AGENTS.md','# Instructions\n');put('README.md','# Fixture\n');put('docs/audits/2026-10-31-android-review.md','# Audit\n\n## AUD-20261031-001\n');save();
 const run=(...a)=>spawnSync(process.execPath,[checker,'--root',root,...a],{encoding:'utf8'});
 try {fn({root,put,task,save,run});}finally {fs.rmSync(root,{recursive:true,force:true});}
}
test('valid records generate deterministic status and stale projection fails',()=>fixture(({put,run})=>{
 assert.equal(run('--write').status,0);assert.equal(run().status,0);
 put('docs/progress/STATUS.md','stale');assert.match(run().stderr,/projection stale/);
}));

test('implemented coverage never increments verified or complete counts',()=>fixture(({root,task,save,run})=>{
 task.status='implemented';task.owner='agent';task.platform='test';task.branch='codex/test';
 task.acceptance_review={local_review:'passed',pending_checks:['android-device','live-backend']};save();
 assert.equal(run('--write').status,0);
 const status=fs.readFileSync(path.join(root,'docs/progress/STATUS.md'),'utf8');
 assert.match(status,/\| M0 \| 1 \/ 1 \| 0 \/ 1 \| 0 \/ 1 \|/);
 assert.match(status,/Local fixtures never establish live backend/);
}));
test('completion requires actual passed category evidence',()=>fixture(({task,save,run})=>{
 task.status='complete';task.owner='agent';task.platform='test';task.branch='test';save();
 const r=run('--write');assert.notEqual(r.status,0);assert.match(r.stderr,/no passed evidence/);
}));

test('latest unverified evidence supersedes a historical pass',()=>fixture(({task,save,put,run})=>{
 task.status='complete';task.owner='agent';task.platform='test';task.branch='test';
 task.verification=['VER-OLD','VER-NEW'];save();
 for(const [id,outcome,time] of [['VER-OLD','passed','2026-10-31T00:00:00Z'],['VER-NEW','unverified','2026-11-01T00:00:00Z']]){
  const m={id,task_ids:['DOC-001'],checks:[{category:'documentation',outcome}],timestamp:time,tested_commit:'abc',dirty_tree:false,environment:'fixture',commands:['fixture']};
  put('docs/verification/'+id+'.md','```json verification-metadata\n'+JSON.stringify(m)+'\n```\n\n## Expected and actual results\n\nFixture.\n\n## Evidence\n\nFixture.\n\n## Limits and next action\n\nFixture.\n');
 }
 assert.match(run('--write').stderr,/no passed evidence/);
}));

test('open acceptance review gates prevent completion',()=>fixture(({task,save,run})=>{
 task.status='complete';task.owner='agent';task.platform='test';task.branch='test';
 task.acceptance_review={pending_checks:['live-backend']};save();
 assert.match(run('--write').stderr,/acceptance review has open checks/);
}));
test('complete task accepts linked passed evidence with explicit environment',()=>fixture(({task,save,put,run})=>{
 task.status='complete';task.owner='agent';task.platform='test';task.branch='test';task.verification=['VER-001'];save();
 const m={id:'VER-001',task_ids:['DOC-001'],checks:[{category:'documentation',outcome:'passed'}],timestamp:'2026-10-31T12:00:00+08:00',tested_commit:'abc',dirty_tree:true,environment:'isolated fixture',commands:['fixture check']};
 put('docs/verification/VER-001.md','```json verification-metadata\n'+JSON.stringify(m)+'\n```\n\n## Expected and actual results\n\nPassed fixture.\n\n## Evidence\n\nFixture execution.\n\n## Limits and next action\n\nNo application evidence claimed.\n');
 assert.equal(run('--write').status,0);assert.equal(run().status,0);
}));
test('missing audit mapping, broken links and dependency cycles fail',()=>fixture(({task,save,put,run})=>{
 task.audit_ids=[];task.dependencies=['DOC-001'];save();put('README.md','[missing](gone.md)');
 const r=run('--write');assert.match(r.stderr,/Unmapped audit/);assert.match(r.stderr,/Dependency cycle/);assert.match(r.stderr,/broken link/);
}));
test('change coverage requires updated task and matching file coverage',()=>fixture(({root,put,run})=>{
 execFileSync('git',['init','--quiet'],{cwd:root});run('--write');
 execFileSync('git',['add','.'],{cwd:root});execFileSync('git',['-c','user.name=Fixture','-c','user.email=fixture@example.test','commit','--quiet','-m','fixture'],{cwd:root});
 put('application.dart','changed');let r=run('--base','HEAD');assert.match(r.stderr,/updated task record/);
 const taskPath=path.join(root,'docs/progress/tasks/DOC-001.md');fs.appendFileSync(taskPath,'\nChange recorded.\n');
 r=run('--base','HEAD');assert.match(r.stderr,/lacks coverage/);
}));
