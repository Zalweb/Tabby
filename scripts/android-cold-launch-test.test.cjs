'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {options, notificationTap} = require('./android-cold-launch-test.cjs');
test('lifecycle runner cannot reboot physical or implicitly selected devices', () => {
  assert.equal(options(['--device', 'emulator-5580', '--mode', 'reboot']).mode, 'reboot');
  for (const args of [[], ['--device', 'USB1234'], ['--device', '192.168.1.2:1234'], ['--device', 'emulator-5580', '--mode', 'other']]) assert.throws(() => options(args));
});
test('native tap uses exact synthetic title and observed valid bounds only', () => {
  assert.deepEqual(notificationTap('<node text="Other notification" bounds="[0,0][100,100]"/><node text="Reminder: Cold launch fixture owes you" bounds="[10,20][110,80]"/>'), [60, 50]);
  for (const xml of ['<node text="Other notification" bounds="[0,0][100,100]"/>', '<node text="Reminder: Cold launch fixture owes you" bounds="[100,0][0,100]"/>', '<node text="Reminder: Cold launch fixture owes you" bounds="[0,0][999999,100]"/>']) assert.throws(() => notificationTap(xml));
});
