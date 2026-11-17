#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const runFile = promisify(execFile);
const {require16kbEmulator} = require('./android-emulator-test.cjs');
const {requireTestApk, validateDriveOutput} = require('./usb-test.cjs');
const root = path.resolve(__dirname, '..');
const testPackage = 'com.zalweb.tabby.usbtest';
const title = 'Reminder: Cold launch fixture owes you';
const caseName = 'native notification cold launch retains payload encrypted draft and PIN';

function options(args) {
  const opts = {mode: 'closed'};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--device', '--mode'].includes(args[i]) || !args[i + 1]) throw Error('Use --device emulator-<port> [--mode closed|reboot].');
    opts[args[i].slice(2)] = args[i + 1];
  }
  if (!/^emulator-\d+$/.test(opts.device || '') || !['closed', 'reboot'].includes(opts.mode)) throw Error('Explicit isolated emulator and bounded lifecycle mode required.');
  return opts;
}

function notificationTap(xml) {
  const node = xml.match(/<node\b[^>]*\btext="Reminder: Cold launch fixture owes you"[^>]*>/)?.[0];
  const m = node?.match(/\bbounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/);
  if (!m) throw Error('Exact synthetic notification is not visible.');
  const [x1, y1, x2, y2] = m.slice(1).map(Number);
  if (x2 <= x1 || y2 <= y1 || x2 > 10000 || y2 > 10000) throw Error('Invalid notification bounds.');
  return [Math.floor((x1 + x2) / 2), Math.floor((y1 + y2) / 2)];
}

async function main() {
  const opts = options(process.argv.slice(2));
  const properties = fs.readFileSync(path.join(root, 'android/local.properties'), 'utf8');
  const property = n => properties.split(/\r?\n/).find(l => l.startsWith(n + '='))?.slice(n.length + 1).replace(/\\\\/g, '\\').replace(/\\:/g, ':');
  const sdk = property('sdk.dir'), flutter = property('flutter.sdk');
  const exe = process.platform === 'win32' ? '.exe' : '';
  const adb = path.join(sdk, 'platform-tools', 'adb' + exe);
  const dart = path.join(flutter, 'bin/cache/dart-sdk/bin', 'dart' + exe);
  const snapshot = path.join(flutter, 'bin/cache/flutter_tools.snapshot');
  const dir = path.join(root, '.dart_tool/lifecycle-tests', new Date().toISOString().replace(/[:.]/g, '-'));
  const uiPath = `/sdcard/tabby-cold-${path.basename(dir)}.xml`;
  fs.mkdirSync(dir, {recursive: true});
  const report = {started_at: new Date().toISOString(), outcome: 'failed', device: opts.device, mode: opts.mode, package: testPackage, steps: [], limitations: ['Synthetic 16KB emulator only; no personal tablet reboot or notification collection.', 'Native OS posting/cold-launch payload and encrypted fixture persistence; not authenticated membership routing or real FCM.']};
  let forwardedPort, authorizedEmulator = false;
  const command = async (name, file, args, timeout = 60000, missing = false) => {
    const step = {name, outcome: 'failed'}, started = Date.now();
    report.steps.push(step);
    process.stdout.write(name + '\n');
    try {
      let output;
      try {
        const r = await runFile(file, args, {cwd: root, timeout, windowsHide: true, maxBuffer: 12 * 1024 * 1024});
        output = r.stdout + r.stderr;
      } catch (e) {
        if (missing && e.code === 1 && !e.stdout?.trim() && !e.stderr?.trim()) output = '';
        else { fs.writeFileSync(path.join(dir, `${report.steps.length}-${name}.log`), (e.stdout || '') + (e.stderr || '')); throw Error(`${name} failed; inspect ignored local log.`); }
      }
      fs.writeFileSync(path.join(dir, `${report.steps.length}-${name}.log`), output);
      step.outcome = 'passed';
      return output.trim();
    } finally { step.duration_ms = Date.now() - started; }
  };
  const device = (n, args, timeout, missing) => command(n, adb, ['-s', opts.device, ...args], timeout, missing);
  const pause = () => new Promise(resolve => setTimeout(resolve, 1000));
  const until = async (callback, timeout = 60000) => {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) { const result = await callback(); if (result) return result; await pause(); }
    throw Error('Bounded native lifecycle condition timed out.');
  };
  const pid = () => device('fixture-pid', ['shell', 'pidof', testPackage], 10000, true);
  const killFixtureProcess = async name => {
    const ownedPid = await pid();
    if (ownedPid) {
      if (!/^\d+$/.test(ownedPid)) throw Error('Unexpected isolated fixture PID.');
      // Android run-as drops to this debug package's UID. SIGKILL simulates
      // process death without force-stopping the package or canceling alarms.
      await device(name, ['shell', 'run-as', testPackage, 'kill', '-9', ownedPid]);
    }
    await until(async () => !(await pid()), 15000);
  };
  const environment = async () => require16kbEmulator(
    await device('qemu', ['shell', 'getprop', 'ro.kernel.qemu']),
    await device('pages', ['shell', 'getconf', 'PAGE_SIZE']),
    await device('abi', ['shell', 'getprop', 'ro.product.cpu.abi']),
  );
  try {
    report.commit = await command('git-head', 'git', ['rev-parse', 'HEAD']);
    report.dirty_tree = Boolean(await command('git-status', 'git', ['status', '--porcelain']));
    await environment();
    authorizedEmulator = true;
    const target = 'integration_test/android_notification_cold_launch_test.dart';
    const defines = ['--dart-define=TABBY_USB_TEST=true'];
    await command('build-fixture', dart, [snapshot, 'build', 'apk', '--debug', `--target=${target}`, ...defines], 15 * 60000);
    const apk = path.join(root, 'build/app/outputs/flutter-apk/app-debug.apk');
    requireTestApk(await command('verify-package', path.join(sdk, 'build-tools/36.0.0', 'aapt' + exe), ['dump', 'badging', apk]));
    report.apk_sha256 = crypto.createHash('sha256').update(fs.readFileSync(apk)).digest('hex');
    fs.copyFileSync(apk, path.join(dir, 'fixture.apk'));
    await environment();
    await device('install-fixture', ['install', '-r', '-t', apk]);
    await device('notification-permission', ['shell', 'pm', 'grant', testPackage, 'android.permission.POST_NOTIFICATIONS']);
    const seed = await command('drive-seed', dart, [snapshot, 'drive', '--no-pub', `--device-id=${opts.device}`, '--driver=test_driver/integration_test.dart', `--target=${target}`, `--use-application-binary=${apk}`, '--keep-app-running', ...defines], 10 * 60000);
    validateDriveOutput(seed, [caseName]);
    const due = Number(seed.match(/NATIVE_COLD seed=true dueEpoch=(\d+)/)?.[1]);
    if (!Number.isSafeInteger(due) || due <= Date.now() + 5000) throw Error('Alarm must still be in the future before lifecycle transition.');
    report.alarm_due_epoch = due;
    await device('home-before-close', ['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
    if (opts.mode === 'reboot') {
      await environment();
      await device('emulator-reboot', ['reboot']);
      await device('wait-disconnected', ['wait-for-disconnect'], 60000);
      await device('wait-reconnected', ['wait-for-device'], 240000);
      await until(async () => (await device('boot-completed', ['shell', 'getprop', 'sys.boot_completed'])) === '1', 240000);
      await environment();
      await device('unlock-test-emulator', ['shell', 'input', 'keyevent', 'KEYCODE_MENU']);
      report.emulator_rebooted = true;
    } else {
      await killFixtureProcess('kill-owned-fixture-process');
      if (Date.now() >= due) throw Error('Process was not gone before the alarm due date.');
      report.process_gone_before_due = true;
    }
    while (Date.now() < due) await pause();
    await device('wake-test-emulator', ['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
    await device('unlock-notification-drawer', ['shell', 'input', 'keyevent', 'KEYCODE_MENU']);
    const tap = await until(async () => {
      await device('expand-synthetic-drawer', ['shell', 'cmd', 'statusbar', 'expand-notifications']);
      const dumped = await device('dump-emulator-ui', ['shell', 'uiautomator', 'dump', '--compressed', uiPath], 30000);
      if (!dumped.includes('dumped to:')) return null;
      const xml = await device('read-emulator-ui', ['shell', 'cat', uiPath]);
      try { return notificationTap(xml); } catch { return null; }
    }, 150000);
    report.actual_notification_visible = true;
    // An alarm receiver can leave a cached Java process. Close it too so the
    // actual drawer tap must create the process and Flutter engine anew.
    await killFixtureProcess('kill-owned-cached-receiver');
    report.process_absent_before_tap = true;
    await device('tap-exact-synthetic-notification', ['shell', 'input', 'tap', ...tap.map(String)]);
    const newPid = await until(pid, 30000);
    if (!/^\d+$/.test(newPid)) throw Error('Unexpected fixture PID.');
    let nativeLog = '';
    const vm = await until(async () => {
      nativeLog = await device('cold-fixture-log', ['logcat', '-d', `--pid=${newPid}`, '-s', 'flutter:I']);
      return nativeLog.match(/Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]+)/)?.[1];
    }, 60000);
    const guest = new URL(vm);
    forwardedPort = await device('forward-cold-vm', ['forward', 'tcp:0', `tcp:${guest.port}`]);
    if (!/^\d+$/.test(forwardedPort)) throw Error('Invalid allocated VM forward.');
    const output = await command('drive-cold-existing-app', dart, [snapshot, 'drive', '--no-pub', `--device-id=${opts.device}`, `--use-existing-app=http://127.0.0.1:${forwardedPort}${guest.pathname}`, '--driver=test_driver/integration_test.dart', `--target=${target}`, '--keep-app-running', ...defines], 10 * 60000);
    nativeLog = await device('cold-fixture-final-log', ['logcat', '-d', `--pid=${newPid}`, '-s', 'flutter:I']);
    validateDriveOutput(output + '\n' + nativeLog, [caseName]);
    if (!nativeLog.includes('NATIVE_COLD launchedFromNotification=true payloadValid=true encryptedDraft=true persistedPin=true')) throw Error('Cold notification launch proof missing.');
    report.cold_launch_payload_and_encrypted_state = 'passed';
    report.outcome = 'passed';
  } catch (e) {
    report.error = e.message;
    process.exitCode = 1;
    process.stderr.write(e.message + '\n');
  } finally {
    try {
      if (forwardedPort) await device('remove-owned-forward', ['forward', '--remove', `tcp:${forwardedPort}`]);
      if (authorizedEmulator) await device('stop-completed-fixture', ['shell', 'am', 'force-stop', testPackage]);
    } catch (e) { report.cleanup_error = e.message; report.outcome = 'failed'; process.exitCode = 1; }
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    process.stdout.write('Report: ' + path.relative(root, path.join(dir, 'report.json')) + '\n');
  }
}
module.exports = {options, notificationTap};
if (require.main === module) main().catch(e => {process.stderr.write(e.message + '\n'); process.exitCode = 1;});
