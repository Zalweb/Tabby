#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const {promisify} = require('node:util');
const {requireTestApk, validateDriveOutput} = require('./usb-test.cjs');
const execFile = promisify(cp.execFile);
const root = path.resolve(__dirname, '..');
const testPackage = 'com.zalweb.tabby.usbtest';

function options(args) {
  const opts = {suite: 'storage'};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--device', '--suite'].includes(args[i]) || !args[i + 1]) throw Error('Use --device emulator-<port> [--suite storage|sessions|notifications|all].');
    opts[args[i].slice(2)] = args[i + 1];
  }
  if (!/^emulator-\d+$/.test(opts.device || '')) throw Error('An explicit Android emulator serial is required; physical/Wi-Fi targets are forbidden.');
  if (!['storage', 'sessions', 'notifications', 'all'].includes(opts.suite)) throw Error('Unknown emulator fixture suite.');
  return opts;
}

function require16kbEmulator(qemu, pageSize, abi) {
  if (qemu.trim() !== '1' || pageSize.trim() !== '16384' || abi.trim() !== 'x86_64') {
    throw Error('Expected an actual 16KB x86_64 Android emulator; no physical or 4KB fallback.');
  }
}

async function main() {
  const opts = options(process.argv.slice(2));
  const properties = fs.readFileSync(path.join(root, 'android/local.properties'), 'utf8');
  const property = name => properties.split(/\r?\n/).find(l => l.startsWith(name + '='))?.slice(name.length + 1).replace(/\\\\/g, '\\').replace(/\\:/g, ':');
  const sdk = property('sdk.dir'), flutter = property('flutter.sdk');
  const exe = process.platform === 'win32' ? '.exe' : '';
  const adb = path.join(sdk, 'platform-tools', 'adb' + exe);
  const dart = path.join(flutter, 'bin/cache/dart-sdk/bin', 'dart' + exe);
  const snapshot = path.join(flutter, 'bin/cache/flutter_tools.snapshot');
  const dir = path.join(root, '.dart_tool/emulator-tests', new Date().toISOString().replace(/[:.]/g, '-'));
  fs.mkdirSync(dir, {recursive: true});
  const report = {started_at: new Date().toISOString(), outcome: 'failed', suite: opts.suite, device: opts.device, package: testPackage, steps: [], limitations: ['Local synthetic fixtures, not real provider/backend or signed-candidate acceptance.', 'x86_64 16KB runtime does not substitute for ARM64 artifact/device acceptance.']};
  const command = async (name, file, args, timeout = 60000) => {
    const step = {name, outcome: 'failed'}, start = Date.now();
    report.steps.push(step);
    process.stdout.write(name + '\n');
    try {
      const result = await execFile(file, args, {cwd: root, timeout, windowsHide: true, maxBuffer: 16 * 1024 * 1024});
      const output = (result.stdout + result.stderr).replace(/(?:eyJ[A-Za-z0-9_-]+\.){2}[A-Za-z0-9_-]+/g, '[redacted-jwt]');
      fs.writeFileSync(path.join(dir, `${report.steps.length}-${name}.log`), output);
      step.outcome = 'passed';
      return output.trim();
    } catch (error) {
      fs.writeFileSync(path.join(dir, `${report.steps.length}-${name}.log`), ((error.stdout || '') + (error.stderr || '')).replace(/(?:eyJ[A-Za-z0-9_-]+\.){2}[A-Za-z0-9_-]+/g, '[redacted-jwt]'));
      throw Error(`${name} failed; see ignored local command log.`);
    } finally { step.duration_ms = Date.now() - start; }
  };
  const device = (name, args) => command(name, adb, ['-s', opts.device, ...args]);
  const identity = async tag => {
    const qemu = await device('qemu-' + tag, ['shell', 'getprop', 'ro.kernel.qemu']);
    const pages = await device('pages-' + tag, ['shell', 'getconf', 'PAGE_SIZE']);
    const abi = await device('abi-' + tag, ['shell', 'getprop', 'ro.product.cpu.abi']);
    require16kbEmulator(qemu, pages, abi);
  };
  try {
    report.commit = await command('git-head', 'git', ['rev-parse', 'HEAD']);
    report.dirty_tree = Boolean(await command('git-status', 'git', ['status', '--porcelain']));
    await identity('preflight');
    report.api = await device('api', ['shell', 'getprop', 'ro.build.version.sdk']);
    report.page_size = 16384;
    const contracts = Object.assign({}, ...['storage', 'session', 'notification'].map(n => JSON.parse(fs.readFileSync(path.join(root, `integration_test/android_${n}_cases.json`), 'utf8'))));
    const suites = {
      storage: ['android_storage_seed_test.dart', 'android_storage_verify_test.dart'],
      sessions: ['android_receiving_scope_test.dart', 'android_auth_completion_test.dart'],
      notifications: ['android_notification_delivery_test.dart', 'android_notification_denied_test.dart'],
    };
    const targets = opts.suite === 'all' ? Object.values(suites).flat() : suites[opts.suite];
    for (const target of targets) {
      const tag = path.basename(target, '.dart');
      const defines = ['--dart-define=TABBY_USB_TEST=true'];
      await command('build-' + tag, dart, [snapshot, 'build', 'apk', '--debug', `--target=integration_test/${target}`, ...defines], 15 * 60000);
      const apk = path.join(root, 'build/app/outputs/flutter-apk/app-debug.apk');
      const versions = fs.readdirSync(path.join(sdk, 'build-tools')).sort((a, b) => b.localeCompare(a, undefined, {numeric: true}));
      requireTestApk(await command('package-' + tag, path.join(sdk, 'build-tools', versions[0], 'aapt' + exe), ['dump', 'badging', apk]));
      await identity(tag);
      await device('install-' + tag, ['install', '-r', '-t', apk]);
      const deny = target === 'android_notification_denied_test.dart';
      if (Number(report.api) < 33) throw Error('This suite requires API33+ native permission controls.');
      await device('permission-' + tag, ['shell', 'pm', deny ? 'revoke' : 'grant', testPackage, 'android.permission.POST_NOTIFICATIONS']);
      try {
        const output = await command('drive-' + tag, dart, [snapshot, 'drive', '--no-pub', `--device-id=${opts.device}`, '--driver=test_driver/integration_test.dart', `--target=integration_test/${target}`, `--use-application-binary=${apk}`, '--keep-app-running', ...defines], 10 * 60000);
        const required = contracts[target];
        if (!Array.isArray(required) || required.length === 0) throw Error('Missing native case contract.');
        const validation = {name: 'validate-' + tag, outcome: 'failed', required_cases: required.length};
        report.steps.push(validation);
        validateDriveOutput(output, required);
        validation.outcome = 'passed';
      } finally {
        if (deny) await device('restore-permission-' + tag, ['shell', 'pm', 'grant', testPackage, 'android.permission.POST_NOTIFICATIONS']);
        await device('stop-' + tag, ['shell', 'am', 'force-stop', testPackage]);
      }
    }
    report.outcome = 'passed';
  } catch (error) {
    report.error = error.message;
    process.exitCode = 1;
    process.stderr.write(error.message + '\n');
  } finally {
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    process.stdout.write('Report: ' + path.relative(root, path.join(dir, 'report.json')) + '\n');
  }
}
module.exports = {options, require16kbEmulator};
if (require.main === module) main().catch(e => {process.stderr.write(e.message + '\n'); process.exitCode = 1;});
