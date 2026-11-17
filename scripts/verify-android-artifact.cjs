'use strict';
const fs=require('node:fs');
const path=require('node:path');
const cp=require('node:child_process');
const crypto=require('node:crypto');
const zlib=require('node:zlib');
function requireHex(value,length,label) {
  if(typeof value!=='string'||!new RegExp(`^[a-f0-9]{${length}}$`,'i').test(value))throw Error(`${label} must be ${length} hexadecimal characters`);
  return value.toLowerCase();
}
function verifyCertificate(text,expected) {
  requireHex(expected,64,'Release certificate');
  const fingerprints=[...text.matchAll(/^Signer #\d+ certificate SHA-256 digest:\s*([a-f0-9]+)\s*$/gmi)].map(m=>m[1].toLowerCase());
  if(/certificate DN:.*(?:Android Debug|CN=debug(?:,|$))/i.test(text))throw Error('Debug signing certificate is forbidden');
  if(fingerprints.length!==1||fingerprints[0]!==expected.toLowerCase())throw Error('APK signing certificate does not match the configured release identity');
  return fingerprints[0];
}
function parsePackage(text) {
  const match=text.match(/^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'/m);
  if(!match||match[1]!=='com.zalweb.tabby')throw Error('Unexpected APK application ID');
  if(/^application-debuggable\b/m.test(text))throw Error('Debuggable APK is forbidden');
  if(!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(match[3])||Number(match[2])<1)throw Error('Invalid APK version');
  return {application_id:match[1],version_code:Number(match[2]),version_name:match[3]};
}
function elfAlignment(bytes,name) {
  if(bytes.length<64||bytes.readUInt32BE(0)!==0x7f454c46||bytes[4]!==2||bytes[5]!==1)throw Error(`Unsupported ELF64 library: ${name}`);
  const offset=Number(bytes.readBigUInt64LE(32)),size=bytes.readUInt16LE(54),count=bytes.readUInt16LE(56);
  if(!Number.isSafeInteger(offset)||size<56||offset+size*count>bytes.length)throw Error(`Invalid ELF headers: ${name}`);
  let loads=0;
  const loadRanges=[],relroRanges=[];
  for(let i=0;i<count;i++) {
    const h=offset+i*size;
    const kind=bytes.readUInt32LE(h);
    if(kind===0x6474e552) {
      const start=bytes.readBigUInt64LE(h+16),length=bytes.readBigUInt64LE(h+40);
      if(length>0n)relroRanges.push({start,end:start+length});
    }
    if(kind!==1)continue;
    loads++;
    const alignment=bytes.readBigUInt64LE(h+48),fileOffset=bytes.readBigUInt64LE(h+8),address=bytes.readBigUInt64LE(h+16);
    if(alignment<16384n||fileOffset%16384n!==address%16384n)throw Error(`ELF LOAD segment is not 16 KB aligned: ${name}`);
    loadRanges.push({start:address,end:address+bytes.readBigUInt64LE(h+40),writable:(bytes.readUInt32LE(h+4)&2)!==0});
  }
  if(!loads)throw Error(`No ELF LOAD segments: ${name}`);
  for(const region of relroRanges) {
    // Linkers may pad RELRO beyond its LOAD's memory end. The actual risk is
    // writable memory in the trailing page that Android will make read-only.
    const parents=loadRanges.filter(load=>region.start>=load.start&&region.start<load.end);
    if(!parents.length)throw Error(`ELF RELRO region is outside LOAD segments: ${name}`);
    const protectedEnd=(region.end+16383n)/16384n*16384n;
    if(protectedEnd>region.end&&loadRanges.some(load=>load.writable&&load.end>region.end&&load.start<protectedEnd)) {
      throw Error(`ELF RELRO end shares writable data in a 16 KB page: ${name}`);
    }
  }
  return {name,load_segments:loads,minimum_alignment:16384,relro_segments:relroRanges.length,relro_16kb_compatible:true};
}
function nativeLibraries(apk) {
  let end=-1;
  for(let i=apk.length-22;i>=Math.max(0,apk.length-65557);i--) {
    if(apk.readUInt32LE(i)===0x06054b50 && i+22+apk.readUInt16LE(i+20)===apk.length){end=i;break;}
  }
  if(end<0)throw Error('APK ZIP directory missing');
  const entries=apk.readUInt16LE(end+10),start=apk.readUInt32LE(end+16);
  if(entries===65535||start===0xffffffff)throw Error('ZIP64 APK is unsupported');
  let cursor=start;
  const libraries=[];
  for(let i=0;i<entries;i++) {
    if(cursor+46>apk.length||apk.readUInt32LE(cursor)!==0x02014b50)throw Error('Invalid APK ZIP directory');
    const compression=apk.readUInt16LE(cursor+10),compressed=apk.readUInt32LE(cursor+20),expanded=apk.readUInt32LE(cursor+24);
    const nameLength=apk.readUInt16LE(cursor+28),extra=apk.readUInt16LE(cursor+30),comment=apk.readUInt16LE(cursor+32);
    const local=apk.readUInt32LE(cursor+42),name=apk.toString('utf8',cursor+46,cursor+46+nameLength);
    cursor+=46+nameLength+extra+comment;
    if(!/^lib\/(arm64-v8a|x86_64)\/[^/]+\.so$/.test(name))continue;
    if(expanded>256*1024*1024||local+30>apk.length||apk.readUInt32LE(local)!==0x04034b50)throw Error('Invalid native ZIP entry');
    const dataStart=local+30+apk.readUInt16LE(local+26)+apk.readUInt16LE(local+28);
    if(dataStart+compressed>apk.length)throw Error('Truncated native ZIP entry');
    const payload=apk.subarray(dataStart,dataStart+compressed);
    const decoded=compression===0?payload:compression===8?zlib.inflateRawSync(payload,{maxOutputLength:256*1024*1024}):null;
    if(!decoded||decoded.length!==expanded)throw Error('Unsupported native ZIP compression');
    libraries.push(elfAlignment(decoded,name));
  }
  if(!libraries.some(lib=>lib.name.startsWith('lib/arm64-v8a/')))throw Error('ARM64 native libraries missing');
  return libraries;
}
function verifyArtifact({apk,sdk,java='java',expectedCert,expectedDigest,commit,output},run=cp.execFileSync) {
  requireHex(commit,40,'Candidate commit'); requireHex(expectedCert,64,'Release certificate');
  if(!sdk)throw Error('Android SDK is required');
  const tools=path.join(sdk,'build-tools','36.0.0'),suffix=process.platform==='win32'?'.exe':'';
  const bytes=fs.readFileSync(apk),digest=crypto.createHash('sha256').update(bytes).digest('hex');
  if(expectedDigest && digest!==requireHex(expectedDigest,64,'APK SHA-256'))throw Error('APK digest differs from verified candidate');
  const invoke=(file,args)=>run(file,args,{encoding:'utf8',maxBuffer:16*1024*1024,stdio:['ignore','pipe','pipe']});
  const certificate=verifyCertificate(invoke(java,['-jar',path.join(tools,'lib','apksigner.jar'),'verify','--verbose','--print-certs',apk]),expectedCert);
  const application=parsePackage(invoke(path.join(tools,'aapt2'+suffix),['dump','badging',apk]));
  invoke(path.join(tools,'zipalign'+suffix),['-c','-P','16','4',apk]);
  const libraries=nativeLibraries(bytes);
  const manifest={schema:1,commit:commit.toLowerCase(),apk_sha256:digest,certificate_sha256:certificate,
    ...application,debuggable:false,zip_16kb_aligned:true,native_libraries:libraries};
  if(output)fs.writeFileSync(output,JSON.stringify(manifest,null,2)+'\n');
  return manifest;
}
module.exports={verifyArtifact,verifyCertificate,parsePackage,elfAlignment,nativeLibraries,requireHex};
if(require.main===module) {
  try {
    const args={};for(let i=2;i<process.argv.length;i+=2)args[process.argv[i]]=process.argv[i+1];
    const manifest=verifyArtifact({apk:args['--apk'],sdk:args['--sdk']??process.env.ANDROID_HOME??process.env.ANDROID_SDK_ROOT,
      java:args['--java']??'java',expectedCert:args['--expected-cert']??process.env.ANDROID_RELEASE_CERT_SHA256,
      expectedDigest:args['--expected-sha256'],commit:args['--commit'],output:args['--output']});
    console.log(`ANDROID_ARTIFACT_OK: ${manifest.application_id} ${manifest.version_name}+${manifest.version_code} ${manifest.apk_sha256}; certificate, ZIP and ELF alignment passed. Device verification is separate.`);
  } catch(error) {console.error('ANDROID_ARTIFACT_REJECTED: '+error.message);process.exitCode=1;}
}
