'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {seal} = require('./azure-full-seal.cjs');
const pair = crypto.generateKeyPairSync('rsa', {modulusLength: 3072});
const pem = pair.publicKey.export({type: 'spki', format: 'pem'});
function open(envelope, privateKey = pair.privateKey) {
  const key = crypto.privateDecrypt({key: privateKey, oaepHash: 'sha256', padding: crypto.constants.RSA_PKCS1_OAEP_PADDING}, Buffer.from(envelope.wrappedKey, 'base64'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]);
}
test('asset snapshot round-trips without exposing its private content', () => {
  const secret = 'synthetic-private-receipt-and-provider-fixture';
  const envelope = seal(pem, Buffer.from(secret));
  assert.equal(open(envelope).toString(), secret);
  assert(!JSON.stringify(envelope).includes(secret));
  assert.notEqual(envelope.ciphertext, seal(pem, Buffer.from(secret)).ciphertext);
});
test('tampered content fails authentication and small/non-RSA keys are rejected', () => {
  const envelope = seal(pem, Buffer.from('synthetic fixture'));
  const bytes = Buffer.from(envelope.ciphertext, 'base64'); bytes[0] ^= 1;
  assert.throws(() => open({...envelope, ciphertext: bytes.toString('base64')}));
  const ec = crypto.generateKeyPairSync('ed25519');
  assert.throws(() => seal(ec.publicKey.export({type: 'spki', format: 'pem'}), Buffer.from('fixture')));
  const weak = crypto.generateKeyPairSync('rsa', {modulusLength: 2048});
  assert.throws(() => seal(weak.publicKey.export({type: 'spki', format: 'pem'}), Buffer.from('fixture')));
});
