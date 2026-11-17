'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { physicalUsbSerial, pairedWifiTarget, validateLiveConfig, requireTestApk, validateDriveOutput, options } = require('./usb-test.cjs');
test('USB selection rejects wireless, emulator and unauthorized output', () => {
  assert.equal(physicalUsbSerial('USB1234\r\n'), 'USB1234');
  for (const serial of ['192.168.1.2:5555', 'adb-id._adb-tls-connect._tcp', 'emulator-5554', 'unknown', '', 'a\nb']) {
    assert.throws(() => physicalUsbSerial(serial));
  }
});
test('Wi-Fi requires explicit local TLS selection and never accepts legacy tcpip discovery', () => {
  const target = '192.168.254.198:38983';
  assert.equal(options(['--transport','wifi','--device',target]).device, target);
  assert.equal(pairedWifiTarget(target, 'adb-fixture\t_adb-tls-connect._tcp\t' + target), target);
  for (const value of ['8.8.8.8:5555','127.0.0.1:5555','host.local:1234','192.168.1.2:0','192.168.1.2:65536','192.168.1.2:5555;cmd']) assert.throws(() => pairedWifiTarget(value));
  assert.throws(() => pairedWifiTarget(target, 'adb-fixture\t_adb._tcp\t' + target));
  assert.throws(() => options(['--device',target]));
  assert.throws(() => options(['--transport','wifi']));
});
test('production APK can never be installed by this runner', () => {
  requireTestApk("package: name='com.zalweb.tabby.entrytest' versionCode='5'", true);
  assert.throws(() => requireTestApk("package: name='com.zalweb.tabby' versionCode='5'", true));
  assert.throws(() => requireTestApk("package: name='com.zalweb.tabby.usbtest' versionCode='5'", true));
  requireTestApk("package: name='com.zalweb.tabby.usbtest' versionCode='5'");
  assert.throws(() => requireTestApk("package: name='com.zalweb.tabby' versionCode='5'"));
  assert.throws(() => requireTestApk("package: name='com.zalweb.tabby'\napplication-label:'package: name='com.zalweb.tabby.usbtest''"));
});
const config = () => ({ SUPABASE_URL: 'https://tabby-test.contoso.net', SUPABASE_ANON_KEY: 'sb_publishable_fixture',
  TABBY_TEST_EMAIL: 'fixture@contoso.net', TABBY_TEST_PASSWORD: 'synthetic-fixture-password', TABBY_LIVE_TEST: 'true' });

test('drive success cannot hide late runtime or framework errors', () => {
  for (const suffix of ['Unhandled Exception: Bad state: registration after execution', 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK', 'Some tests failed']) {
    assert.throws(() => validateDriveOutput('All tests passed!\n' + suffix));
  }
  assert.throws(() => validateDriveOutput('Process exited with code 0'));
});
test('device success requires every contracted case to have run', () => {
  validateDriveOutput('case one\ncase two\nAll tests passed!', ['case one', 'case two']);
  assert.throws(() => validateDriveOutput('case one\nAll tests passed!', ['case one', 'case two']));
});
test('session contract rejects the observed empty native receiving pass', () => {
  const cases = require('../integration_test/android_session_cases.json');
  assert.equal(cases['android_receiving_scope_test.dart'].length, 22);
  assert.equal(cases['android_auth_completion_test.dart'].length, 22);
  assert.throws(() => validateDriveOutput('00:00 +1: All tests passed!', cases['android_receiving_scope_test.dart']));
});
test('live tests require explicit HTTPS target and client-only key', () => {
  validateLiveConfig(config());
  // Admin-created synthetic Auth accounts can intentionally use .invalid.
  validateLiveConfig({...config(), TABBY_TEST_EMAIL: 'synthetic-qa@example.invalid'});
  for (const changes of [{ SUPABASE_URL: 'http://localhost' }, { SUPABASE_URL: 'https://ziaqrkagsvozhotremsx.supabase.co' },
    { SUPABASE_ANON_KEY: 'sb_secret_fixture' }, { SUPABASE_ANON_KEY: `x.${Buffer.from('{"role":"service_role"}').toString('base64url')}.x` },
    { TABBY_TEST_PASSWORD: '' }, { TABBY_LIVE_TEST: 'false' }, { SERVICE_ROLE_KEY: 'secret' }]) {
    assert.throws(() => validateLiveConfig({ ...config(), ...changes }));
  }
  validateLiveConfig({ ...config(), SUPABASE_ANON_KEY: `x.${Buffer.from('{"role":"anon"}').toString('base64url')}.x` });
});
test('invalid options cannot introduce shell commands or unbounded repetition', () => {
  assert.equal(options([]).suite, 'smoke');
  assert.equal(options(['--suite', 'matrix', '--repeat', '2']).repeat, 2);
  assert.equal(options(['--suite', 'sessions', '--transport', 'wifi', '--device', '192.168.1.2:12345']).suite, 'sessions');
  assert.equal(options(['--suite', 'notifications']).suite, 'notifications');
  assert.equal(options(['--suite', 'entry']).suite, 'entry');
  for (const args of [['--suite', 'other'], ['--repeat', '0'], ['--repeat', '21'], ['--repeat', 'NaN'], ['--shell', 'x']]) {
    assert.throws(() => options(args));
  }
});

test('Google-only entry device contract requires real artwork and scoped setup cases', () => {
  const cases = require('../integration_test/android_google_entry_cases.json')['android_google_entry_test.dart'];
  assert.equal(cases.length, 6);
  assert.ok(cases.some(name => name.includes('mascot artwork animates')));
  assert.throws(() => validateDriveOutput('All tests passed!', cases));
  assert.throws(() => validateDriveOutput(cases.slice(0, 4).join('\n') + '\nAll tests passed!', cases));
  validateDriveOutput(cases.join('\n') + '\nAll tests passed!', cases);
});

test('notification acceptance requires native delivery and denied-permission cases', () => {
  const contract = require('../integration_test/android_notification_cases.json');
  const cases = contract['android_notification_delivery_test.dart'];
  assert.equal(cases.length, 3);
  assert.throws(() => validateDriveOutput('All tests passed!', cases));
  validateDriveOutput(cases.join('\n') + '\nAll tests passed!', cases);
  const denied = contract['android_notification_denied_test.dart'];
  assert.equal(denied.length, 1);
  assert.throws(() => validateDriveOutput('All tests passed!', denied));
  validateDriveOutput(denied.join('\n') + '\nAll tests passed!', denied);
});

test('expense entry suite requires all sixteen form and native storage cases', () => {
  assert.equal(options(['--suite', 'expense-entry']).suite, 'expense-entry');
  const contract = require('../integration_test/android_expense_entry_cases.json');
  const cases = Object.values(contract).flat();
  assert.equal(cases.length, 16);
  assert.throws(() => validateDriveOutput(cases.slice(0, 15).join('\n') + '\nAll tests passed!', cases));
  validateDriveOutput(cases.join('\n') + '\nAll tests passed!', cases);
});
