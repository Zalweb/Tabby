#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
function seal(publicKeyPem, plaintext) {
  const publicKey = crypto.createPublicKey(publicKeyPem);
  if (publicKey.asymmetricKeyType !== 'rsa' || publicKey.asymmetricKeyDetails.modulusLength < 3072) {
    throw Error('Migration public key must be RSA with at least 3072 bits.');
  }
  const key = crypto.randomBytes(32);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const wrappedKey = crypto.publicEncrypt({key: publicKey, oaepHash: 'sha256', padding: crypto.constants.RSA_PKCS1_OAEP_PADDING}, key);
  key.fill(0);
  return {version: 1, algorithm: 'RSA-OAEP-SHA256+A256GCM', wrappedKey: wrappedKey.toString('base64'),
    iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), ciphertext: ciphertext.toString('base64')};
}
module.exports = {seal};
if (require.main === module) {
  const input = fs.readFileSync(0);
  fs.writeFileSync(process.argv[3], JSON.stringify(seal(fs.readFileSync(process.argv[2]), input)) + '\n', {mode: 0o600});
  input.fill(0);
  console.log('Encrypted migration asset snapshot saved. No plaintext export written.');
}
