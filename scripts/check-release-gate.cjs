'use strict';
const fs=require('node:fs');
const path=require('node:path');
const cp=require('node:child_process');
const {requireHex}=require('./verify-android-artifact.cjs');
const categories=['regression','analysis','integration','backend-integration','android-device','upgrade','oauth','16kb-device','release-artifact','release-authorization'];
function metadata(root,file,label) {
  const resolved=path.resolve(root,file),base=path.resolve(root)+path.sep;
  if(!resolved.startsWith(base))throw Error('Evidence path escapes repository');
  const text=fs.readFileSync(resolved,'utf8');
  const match=text.match(new RegExp('```json '+label+'\\s*\\n([\\s\\S]*?)\\n```'));
  if(!match)throw Error(`Missing ${label}: ${file}`);
  return JSON.parse(match[1]);
}
function checkGate(root,manifest,changedFiles=[]) {
  const commit=requireHex(manifest.commit,40,'Candidate commit');
  requireHex(manifest.apk_sha256,64,'Candidate digest');
  requireHex(manifest.certificate_sha256,64,'Candidate certificate');
  if(manifest.application_id!=='com.zalweb.tabby'||manifest.debuggable!==false||manifest.zip_16kb_aligned!==true||!manifest.native_libraries?.length)throw Error('Artifact manifest is incomplete');
  if(changedFiles.some(file=>file && !file.startsWith('docs/')))throw Error('Application/build sources changed after the tested candidate; rebuild and retest');
  const candidatePath=path.join(root,'docs/releases',commit+'.json');
  if(!fs.existsSync(candidatePath))throw Error('Reviewed candidate evidence missing');
  const candidate=JSON.parse(fs.readFileSync(candidatePath,'utf8'));
  for(const field of ['commit','apk_sha256','certificate_sha256','application_id','version_name','version_code']) {
    if(candidate[field]!==manifest[field])throw Error(`Candidate evidence mismatch: ${field}`);
  }
  if(candidate.release_tag!==`v${manifest.version_name}+${manifest.version_code}`)throw Error('Candidate tag does not match APK version');
  const taskIds=new Set(); let m1Tasks=0;
  for(const name of fs.readdirSync(path.join(root,'docs/progress/tasks'))) {
    if(!name.endsWith('.md'))continue;
    const task=metadata(root,'docs/progress/tasks/'+name,'task-metadata');
    taskIds.add(task.id); if(task.milestone==='M1')m1Tasks++;
    if((task.milestone==='M1'||['QA-001','REL-001'].includes(task.id))&&task.status!=='complete')throw Error(`Release task remains open: ${task.id}`);
  }
  if(!m1Tasks||!taskIds.has('QA-001')||!taskIds.has('REL-001'))throw Error('Required release task inventory missing');
  for(const category of categories) {
    const link=candidate.checks?.find(check=>check.category===category);
    if(!link?.evidence?.startsWith('docs/verification/'))throw Error(`Candidate evidence required: ${category}`);
    const evidence=metadata(root,link.evidence,'verification-metadata');
    if(evidence.tested_commit!==commit||evidence.dirty_tree!==false||
       evidence.apk_sha256!==manifest.apk_sha256||evidence.certificate_sha256!==manifest.certificate_sha256||
       !evidence.environment?.trim()||!evidence.checks?.some(check=>check.category===category&&check.outcome==='passed')) {
      throw Error(`Candidate check not verified on this exact artifact: ${category}`);
    }
  }
  return candidate;
}
module.exports={checkGate,categories};
if(require.main===module) {
  try {
    const args={};for(let i=2;i<process.argv.length;i+=2)args[process.argv[i]]=process.argv[i+1];
    const root=path.resolve(args['--root']??path.join(__dirname,'..'));
    const manifest=JSON.parse(fs.readFileSync(args['--manifest'],'utf8'));
    requireHex(manifest.commit,40,'Candidate commit');
    cp.execFileSync('git',['merge-base','--is-ancestor',manifest.commit,'HEAD'],{cwd:root,stdio:'pipe'});
    const changed=cp.execFileSync('git',['diff','--name-only',manifest.commit,'HEAD'],{cwd:root,encoding:'utf8'}).trim().split(/\r?\n/);
    const candidate=checkGate(root,manifest,changed);
    console.log('RELEASE_GATE_OK: '+candidate.release_tag+'; exact candidate evidence and authorization passed.');
  } catch(error) {console.error('RELEASE_GATE_REJECTED: '+error.message);process.exitCode=1;}
}
