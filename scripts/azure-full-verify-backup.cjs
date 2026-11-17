#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
const {gunzipSync} = require('node:zlib');
function open(file, privateKey) {
  const envelope = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (envelope.version !== 1 || envelope.algorithm !== 'RSA-OAEP-SHA256+A256GCM') throw Error('Unsupported backup envelope.');
  const key = crypto.privateDecrypt({key: privateKey, oaepHash: 'sha256', padding: crypto.constants.RSA_PKCS1_OAEP_PADDING}, Buffer.from(envelope.wrappedKey, 'base64'));
  try {
    const cipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64'));
    cipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
    return Buffer.concat([cipher.update(Buffer.from(envelope.ciphertext, 'base64')), cipher.final()]);
  } finally {key.fill(0);}
}
function main() {
  const recoveryKey = fs.readFileSync(0);
  let vmKey, archive;
  try {
    vmKey = open(process.argv[2], recoveryKey);
    archive = gunzipSync(open(process.argv[3], vmKey));
    const files = new Map();
    for (let offset = 0; offset + 512 <= archive.length;) {
      const header = archive.subarray(offset, offset + 512);
      const name = header.subarray(0,100).toString().replace(/\0.*$/, '');
      if (!name) break;
      const size = parseInt(header.subarray(124,136).toString().replace(/\0.*$/, '').trim(), 8);
      if (!Number.isSafeInteger(size) || size < 0 || offset + 512 + size > archive.length) throw Error('Invalid backup archive.');
      files.set(name, archive.subarray(offset + 512, offset + 512 + size));
      offset += 512 + Math.ceil(size / 512) * 512;
    }
    const manifest = JSON.parse(files.get('manifest.json'));
    for (const [mode, expected] of Object.entries(manifest.files)) {
      const data = files.get(mode + '.sql');
      if (!data || data.length !== expected.bytes || crypto.createHash('sha256').update(data).digest('hex') !== expected.sha256) throw Error('Recovered database dump integrity failed.');
    }
    console.log(JSON.stringify({outcome: 'passed', off_vm_key_recovery: true, run_id: manifest.run_id, tables: manifest.tables, source: manifest.source, database_files_verified: Object.keys(manifest.files).length}));
  } finally {recoveryKey.fill(0); vmKey?.fill(0); archive?.fill(0);}
}
module.exports = {open};
if (require.main === module) try {main();} catch {console.error('Protected backup verification failed; private contents withheld.'); process.exitCode = 1;}
