'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {options, requirePublicConfig} = require('./android-signed-storage-test.cjs');

test('signed production-ID rehearsal rejects physical and implicit targets', () => {
  const args = ['--device', 'emulator-5580', '--baseline-apk', 'private.apk', '--public-config', 'private.json', '--expected-cert', 'a'.repeat(64)];
  assert.equal(options(args).device, 'emulator-5580');
  for (const device of ['HA27LVV6', '192.168.1.2:9999', '']) {
    const changed = [...args]; changed[1] = device;
    assert.throws(() => options(changed));
  }
  assert.throws(() => options([]));
});

test('restoration build cannot embed fixture passwords or privileged keys', () => {
  const config = role => ({SUPABASE_URL: 'https://example.invalid', SUPABASE_ANON_KEY: 'e30.' + Buffer.from(JSON.stringify({role})).toString('base64url') + '.synthetic'});
  assert.doesNotThrow(() => requirePublicConfig(config('anon')));
  assert.throws(() => requirePublicConfig({...config('anon'), TABBY_TEST_PASSWORD: 'synthetic'}));
  assert.throws(() => requirePublicConfig(config('service_role')));
  assert.throws(() => requirePublicConfig({...config('anon'), SUPABASE_URL: 'http://example.invalid'}));
});
