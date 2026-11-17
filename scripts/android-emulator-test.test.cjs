'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {options, require16kbEmulator} = require('./android-emulator-test.cjs');
test('16KB runner requires explicit emulator and bounded local fixture suite', () => {
  assert.deepEqual(options(['--device', 'emulator-5580']), {suite: 'storage', device: 'emulator-5580'});
  assert.equal(options(['--device', 'emulator-5580', '--suite', 'all']).suite, 'all');
  for (const args of [[], ['--device', '192.168.1.2:1234'], ['--device', 'USB1234'], ['--device', 'emulator-5580', '--suite', 'live'], ['--device', 'emulator-5580', '--required-page-size', '4096']]) assert.throws(() => options(args));
});
test('16KB environment cannot be inferred from emulator name or image label', () => {
  require16kbEmulator('1\n', '16384\n', 'x86_64\n');
  for (const input of [['0', '16384', 'x86_64'], ['1', '4096', 'x86_64'], ['1', '16384', 'arm64-v8a']]) assert.throws(() => require16kbEmulator(...input));
});
