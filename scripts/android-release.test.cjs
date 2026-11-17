'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {verifyArtifact,verifyCertificate,parsePackage,elfAlignment,nativeLibraries}=require('./verify-android-artifact.cjs');
const {checkGate,categories}=require('./check-release-gate.cjs');
const CERT='a'.repeat(64),COMMIT='b'.repeat(40);
const SIGNED=`Signer #1 certificate DN: CN=Synthetic Release\nSigner #1 certificate SHA-256 digest: ${CERT}\n`;
const PACKAGE="package: name='com.zalweb.tabby' versionCode='5' versionName='1.0.4' platformBuildVersionName='16'\n";
function elf(alignment=16384n) {
 const b=Buffer.alloc(120);b.writeUInt32BE(0x7f454c46);b[4]=2;b[5]=1;b.writeBigUInt64LE(64n,32);b.writeUInt16LE(56,54);b.writeUInt16LE(1,56);b.writeUInt32LE(1,64);b.writeBigUInt64LE(alignment,112);return b;
}
function relroElf({end=0x2000n,loadEnd=0x6000n,relroStart=0x1000n}={}) {
 const b=Buffer.alloc(176);elf().copy(b);b.writeUInt16LE(2,56);
 b.writeUInt32LE(2,68);b.writeBigUInt64LE(loadEnd,104);
 b.writeUInt32LE(0x6474e552,120);b.writeBigUInt64LE(relroStart,136);b.writeBigUInt64LE(end-relroStart,160);
 return b;
}
function zip(payload=elf(),name='lib/arm64-v8a/libfixture.so') {
 const n=Buffer.from(name),local=Buffer.alloc(30),central=Buffer.alloc(46),end=Buffer.alloc(22);
 local.writeUInt32LE(0x04034b50);local.writeUInt32LE(payload.length,18);local.writeUInt32LE(payload.length,22);local.writeUInt16LE(n.length,26);
 central.writeUInt32LE(0x02014b50);central.writeUInt32LE(payload.length,20);central.writeUInt32LE(payload.length,24);central.writeUInt16LE(n.length,28);
 end.writeUInt32LE(0x06054b50);end.writeUInt16LE(1,8);end.writeUInt16LE(1,10);end.writeUInt32LE(central.length+n.length,12);end.writeUInt32LE(local.length+n.length+payload.length,16);
 return Buffer.concat([local,n,payload,central,n,end]);
}
function fixture() {
 const root=path.resolve('.dart_tool/release-fixtures',crypto.randomUUID());
 fs.mkdirSync(root,{recursive:true});return root; // Synthetic, ignored; no real keys/data.
}
test('certificate verification rejects debug, missing, extra and unexpected signers',()=>{
 assert.equal(verifyCertificate(SIGNED,CERT),CERT);
 assert.throws(()=>verifyCertificate(SIGNED.replace('Synthetic Release','Android Debug'),CERT),/Debug/);
 assert.throws(()=>verifyCertificate(SIGNED,'c'.repeat(64)),/release identity/);
 assert.throws(()=>verifyCertificate(SIGNED+SIGNED.replaceAll('#1','#2'),CERT),/release identity/);
 assert.throws(()=>verifyCertificate('',CERT),/release identity/);
 assert.throws(()=>verifyCertificate(SIGNED,''),/64 hexadecimal/);
});
test('manifest rejects debuggable, wrong package and invalid version',()=>{
 assert.equal(parsePackage(PACKAGE).version_code,5);
 assert.throws(()=>parsePackage(PACKAGE+'application-debuggable\n'),/Debuggable/);
 assert.throws(()=>parsePackage(PACKAGE.replace('com.zalweb.tabby','other.app')),/application ID/);
 assert.throws(()=>parsePackage(PACKAGE.replace('1.0.4','bad-version')),/version/);
});
test('ELF and APK parsing verify actual LOAD alignment and reject malformed inputs',()=>{
 assert.equal(elfAlignment(elf(),'fixture.so').load_segments,1);
 assert.throws(()=>elfAlignment(elf(4096n),'fixture.so'),/16 KB/);
 const mismatched=elf();mismatched.writeBigUInt64LE(4096n,80);
 assert.throws(()=>elfAlignment(mismatched,'fixture.so'),/16 KB/);
 assert.equal(nativeLibraries(zip()).length,1);
 assert.throws(()=>nativeLibraries(zip(elf(4096n))),/16 KB/);
 assert.throws(()=>nativeLibraries(zip(elf(),'assets/fixture.so')),/ARM64/);
 assert.throws(()=>nativeLibraries(Buffer.alloc(0)),/ZIP/);
 assert.throws(()=>elfAlignment(Buffer.alloc(64),'bad.so'),/ELF64/);
});

test('ELF rejects unaligned RELRO that shares a writable LOAD tail',()=>{
 assert.throws(()=>elfAlignment(relroElf(),'unsafe-relro.so'),/RELRO/);
});
test('ELF accepts aligned RELRO and a RELRO ending at its LOAD boundary',()=>{
 assert.equal(elfAlignment(relroElf({end:0x4000n}),'aligned-relro.so').relro_segments,1);
 assert.equal(elfAlignment(relroElf({end:0x6000n}),'tail-free-relro.so').relro_segments,1);
});
test('ELF rejects a RELRO region outside all LOAD segments',()=>{
 assert.throws(()=>elfAlignment(relroElf({loadEnd:0x800n}),'invalid-relro.so'),/RELRO/);
});
test('ELF accepts linker RELRO padding beyond the LOAD memory end',()=>{
 assert.equal(elfAlignment(relroElf({relroStart:0n,end:0x1000n,loadEnd:0x268n}),'padded-relro.so').relro_segments,1);
});
test('ELF rejects a separate writable LOAD in the RELRO trailing page',()=>{
 const b=Buffer.alloc(232);relroElf({end:0x6000n}).copy(b);b.writeUInt16LE(3,56);
 b.writeUInt32LE(1,176);b.writeUInt32LE(2,180);b.writeBigUInt64LE(0x3000n,184);
 b.writeBigUInt64LE(0x7000n,192);b.writeBigUInt64LE(1n,216);b.writeBigUInt64LE(0x4000n,224);
 assert.throws(()=>elfAlignment(b,'trailing-load.so'),/RELRO/);
});
test('artifact gate binds exact bytes and runs signer, manifest and ZIP verification',()=>{
 const root=fixture(),apk=path.join(root,'synthetic.apk');fs.writeFileSync(apk,zip());
 const calls=[];
 const run=(file,args)=>{calls.push([file,args]);return args.includes('verify')?SIGNED:args.includes('badging')?PACKAGE:'';};
 const options={apk,sdk:root,expectedCert:CERT,commit:COMMIT};
 const manifest=verifyArtifact(options,run);
 assert.equal(manifest.apk_sha256,crypto.createHash('sha256').update(fs.readFileSync(apk)).digest('hex'));
 assert.equal(manifest.native_libraries.length,1);assert.equal(calls.length,3);
 assert(calls[2][1].includes('16'));
 assert.throws(()=>verifyArtifact({...options,expectedDigest:'c'.repeat(64)},run),/digest differs/);
 assert.throws(()=>verifyArtifact(options,(file,args)=>{if(args.includes('-P'))throw Error('zipalign rejected');return run(file,args);}),/zipalign rejected/);
});
function candidateFixture() {
 const root=fixture(),manifest={schema:1,commit:COMMIT,apk_sha256:'c'.repeat(64),certificate_sha256:CERT,
  application_id:'com.zalweb.tabby',version_name:'1.0.4',version_code:5,debuggable:false,zip_16kb_aligned:true,native_libraries:[{name:'synthetic.so'}]};
 for(const dir of ['docs/releases','docs/progress/tasks','docs/verification'])fs.mkdirSync(path.join(root,dir),{recursive:true});
 for(const [id,milestone]of [['FIX-001','M1'],['QA-001','M3'],['REL-001','M3']])writeMetadata(root,`docs/progress/tasks/${id}.md`,'task-metadata',{id,milestone,status:'complete'});
 const candidate={...manifest,release_tag:'v1.0.4+5',checks:categories.map(category=>({category,evidence:'docs/verification/VER-SYNTHETIC.md'}))};
 fs.writeFileSync(path.join(root,'docs/releases',COMMIT+'.json'),JSON.stringify(candidate));
 const evidence={tested_commit:COMMIT,dirty_tree:false,apk_sha256:manifest.apk_sha256,certificate_sha256:CERT,environment:'Synthetic unit fixture only; not actual device/release verification',checks:categories.map(category=>({category,outcome:'passed'}))};
 writeMetadata(root,'docs/verification/VER-SYNTHETIC.md','verification-metadata',evidence);
 return {root,manifest,candidate,evidence};
}
function writeMetadata(root,file,label,value){fs.writeFileSync(path.join(root,file),'```json '+label+'\n'+JSON.stringify(value)+'\n```\n');}
test('candidate gate requires exact artifact evidence, completed tasks and documentation-only descendant',()=>{
 const {root,manifest}=candidateFixture();
 assert.equal(checkGate(root,manifest,['docs/verification/VER.md']).release_tag,'v1.0.4+5');
 assert.throws(()=>checkGate(root,manifest,['lib/main.dart']),/sources changed/);
 writeMetadata(root,'docs/progress/tasks/QA-001.md','task-metadata',{id:'QA-001',milestone:'M3',status:'planned'});
 assert.throws(()=>checkGate(root,manifest),/QA-001/);
});
test('candidate gate rejects unverified status, dirty tree and mismatched digest/commit',()=>{
 for(const changed of [{dirty_tree:true},{tested_commit:'d'.repeat(40)},{apk_sha256:'e'.repeat(64)},
  {checks:categories.map(category=>({category,outcome:'unverified'}))}]) {
   const {root,manifest,evidence}=candidateFixture();
   writeMetadata(root,'docs/verification/VER-SYNTHETIC.md','verification-metadata',{...evidence,...changed});
   assert.throws(()=>checkGate(root,manifest),/not verified/);
 }
 const {root,manifest,candidate}=candidateFixture();
 fs.writeFileSync(path.join(root,'docs/releases',COMMIT+'.json'),JSON.stringify({...candidate,apk_sha256:'f'.repeat(64)}));
 assert.throws(()=>checkGate(root,manifest),/evidence mismatch/);
});
test('candidate gate requires authorization and rejects evidence outside repository',()=>{
 const {root,manifest,candidate}=candidateFixture();
 fs.writeFileSync(path.join(root,'docs/releases',COMMIT+'.json'),JSON.stringify({...candidate,checks:candidate.checks.filter(c=>c.category!=='release-authorization')}));
 assert.throws(()=>checkGate(root,manifest),/release-authorization/);
 candidate.checks[0].evidence='docs/verification/../../../outside.md';
 fs.writeFileSync(path.join(root,'docs/releases',COMMIT+'.json'),JSON.stringify(candidate));
 assert.throws(()=>checkGate(root,manifest),/escapes repository/);
});
test('only gated manual publication can write a GitHub release',()=>{
 const directory=path.join(__dirname,'../.github/workflows');
 const workflows=fs.readdirSync(directory).filter(n=>n.endsWith('.yml')).map(n=>[n,fs.readFileSync(path.join(directory,n),'utf8')]);
 const publishers=workflows.filter(([,text])=>text.includes('softprops/action-gh-release'));
 assert.deepEqual(publishers.map(([name])=>name),['publish-latest-build.yml']);
 const publisher=publishers[0][1];
 assert(!publisher.includes('workflow_run:'));assert(publisher.includes('workflow_call:'));
 assert(publisher.indexOf('check-release-gate.cjs')<publisher.indexOf('softprops/action-gh-release'));
 assert(publisher.indexOf('verify-android-artifact.cjs')<publisher.indexOf('softprops/action-gh-release'));
 assert(publisher.includes("github.ref == 'refs/heads/main'"));assert(publisher.includes('environment: android-release'));
 const manual=workflows.find(([name])=>name==='publish-release-apk.yml')[1];
 assert(manual.includes('workflow_dispatch:'));assert(manual.includes('candidate_commit:'));
 const gradle=fs.readFileSync(path.join(__dirname,'../android/app/build.gradle.kts'),'utf8');
 assert(!gradle.includes('getByName("debug")'));assert(gradle.includes('Release signing is required'));
});
