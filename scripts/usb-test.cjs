#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const { promisify } = require('node:util');
const execFile = promisify(cp.execFile);
const root = path.resolve(__dirname, '..');
const testPackage = 'com.zalweb.tabby.usbtest';
const {isIP} = require('node:net');

function physicalUsbSerial(output) {
  const serial = output.trim();
  if (!/^[a-zA-Z0-9_-]+$/.test(serial) || /^emulator-/i.test(serial) || serial === 'unknown') {
    throw Error('Exactly one authorized physical USB device is required. Wireless ADB is not supported.');
  }
  return serial;
}

function pairedWifiTarget(value, services) {
  const [host, port, extra] = value.split(':');
  if (extra || isIP(host) !== 4 || !/^(?:10\.|192\.168\.|172\.(?:1[6-9]|2[0-9]|3[01])\.)/.test(host) || !/^\d{1,5}$/.test(port || '') || Number(port) < 1 || Number(port) > 65535) throw Error('Wi-Fi testing requires an explicit private IPv4 address and TLS debugging port.');
  if (services !== undefined && !services.split(/\r?\n/).some(line => /_adb-tls-connect\._tcp\.?\s/.test(line) && line.trim().split(/\s+/).at(-1) === value)) throw Error('The selected address must advertise Android paired TLS debugging.');
  return value;
}

function validateLiveConfig(config) {
  const required = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'TABBY_TEST_EMAIL', 'TABBY_TEST_PASSWORD'];
  const allowed = new Set([...required, 'TABBY_LIVE_TEST']);
  if (Object.keys(config).some(key => !allowed.has(key))) throw Error('Unexpected live test configuration key.');
  for (const key of required) {
    if (typeof config[key] !== 'string' || !config[key].trim() || /CHANGE_ME/i.test(config[key])) {
      throw Error(`Set ${key} in the private live configuration file.`);
    }
  }
  const url = new URL(config.SUPABASE_URL);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw Error('The live backend must use an HTTPS origin.');
  }
  if (url.hostname === 'ziaqrkagsvozhotremsx.supabase.co') throw Error('The current production backend is not a migration test target.');
  const key = config.SUPABASE_ANON_KEY;
  if (!key.startsWith('sb_publishable_')) {
    let payload;
    try { payload = JSON.parse(Buffer.from(key.split('.')[1], 'base64url')); } catch { /* fail closed below */ }
    if (payload?.role !== 'anon') throw Error('Only an anon/publishable client key is allowed, never a service-role key.');
  }
  if (config.TABBY_LIVE_TEST !== 'true') throw Error('TABBY_LIVE_TEST must explicitly be true.');
  return config;
}

function requireTestApk(badging, entry = false) {
  const packageName = badging.match(/^package: name='([^']+)'/m)?.[1];
  if (packageName !== (entry ? 'com.zalweb.tabby.entrytest' : testPackage)) throw Error('Refusing to install an APK outside the isolated test package.');
}

function validateDriveOutput(output, requiredCases = []) {
  if (!output.includes('All tests passed!') || /Unhandled Exception:|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|Some tests failed|Test failed\./.test(output)) {
    throw Error('Drive output does not establish a clean test pass.');
  }
  for (const name of requiredCases) {
    if (!output.includes(name)) throw Error(`Required device case did not run: ${name}`);
  }
}

function options(args) {
  const result = { suite: 'smoke', repeat: 1, transport: 'usb' };
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (!['--suite', '--repeat', '--live-config', '--flutter-root', '--android-sdk', '--transport', '--device'].includes(flag) || !args[i + 1]) {
      throw Error('Usage: node scripts/usb-test.cjs [--suite preflight|smoke|matrix|sessions|notifications|live] [--repeat 1..20] [--live-config .env.usb-live.json] [--transport wifi --device <private-IP:TLS-port>]');
    }
    result[flag.slice(2)] = args[++i];
  }
  if (!['preflight', 'smoke', 'matrix', 'sessions', 'notifications', 'entry', 'expense-entry', 'live'].includes(result.suite)) throw Error('Unknown USB test suite.');
  result.repeat = Number(result.repeat);
  if (!Number.isInteger(result.repeat) || result.repeat < 1 || result.repeat > 20) throw Error('Repeat must be an integer in 1..20.');
  if (!['usb', 'wifi'].includes(result.transport) || (result.transport === 'usb' && result.device)) throw Error('Use USB by default or explicitly select a Wi-Fi device.');
  if (result.transport === 'wifi') pairedWifiTarget(result.device || '');
  return result;
}

async function main() {
  const opts = options(process.argv.slice(2));
  const entryPackage = ['entry', 'expense-entry'].includes(opts.suite);
  const deviceTestPackage = entryPackage ? 'com.zalweb.tabby.entrytest' : testPackage;
  const reportDir = path.join(root, '.dart_tool', 'usb-tests', new Date().toISOString().replace(/[:.]/g, '-'));
  fs.mkdirSync(reportDir, { recursive: true });
  const report = { started_at: new Date().toISOString(), suite: opts.suite, transport: opts.transport === 'usb' ? 'usb-only' : 'paired-wifi', package: deviceTestPackage,
    outcome: 'failed', steps: [], limitations: ['Synthetic device suites do not verify a live backend.',
      'Matrix delivery probes schedule alarms; notification delivery is not asserted.',
      'No release, upgrade, production migration or full device acceptance is implied.'] };
  const properties = fs.readFileSync(path.join(root, 'android', 'local.properties'), 'utf8');
  const property = name => properties.split(/\r?\n/).find(line => line.startsWith(`${name}=`))?.slice(name.length + 1).replace(/\\\\/g, '\\').replace(/\\:/g, ':');
  const sdk = opts['android-sdk'] || process.env.ANDROID_SDK_ROOT || process.env.ANDROID_HOME || property('sdk.dir');
  const flutter = opts['flutter-root'] || process.env.FLUTTER_ROOT || property('flutter.sdk');
  const exe = process.platform === 'win32' ? '.exe' : '';
  const adb = path.join(sdk, 'platform-tools', `adb${exe}`);
  const dart = path.join(flutter, 'bin', 'cache', 'dart-sdk', 'bin', `dart${exe}`);
  const snapshot = path.join(flutter, 'bin', 'cache', 'flutter_tools.snapshot');
  let privateValues = [];
  const redact = value => privateValues.reduce((s, secret) => s.split(secret).join('[redacted]'), String(value))
    .replace(/(?:eyJ[A-Za-z0-9_-]+\.){2}[A-Za-z0-9_-]+/g, '[redacted-jwt]');
  const command = async (name, file, args, timeout = 60000) => {
    const started = Date.now();
    const step = { name, outcome: 'failed' };
    report.steps.push(step);
    process.stdout.write(`${name}\n`);
    try {
      const output = await execFile(file, args, { cwd: root, timeout, maxBuffer: 12 * 1024 * 1024, windowsHide: true });
      step.outcome = 'passed';
      fs.writeFileSync(path.join(reportDir, `${report.steps.length}-${name}.log`), redact(output.stdout + output.stderr));
      return output.stdout.trim();
    } catch (error) {
      const log = redact((error.stdout || '') + (error.stderr || ''));
      fs.writeFileSync(path.join(reportDir, `${report.steps.length}-${name}.log`), log);
      step.exit_code = error.code;
      step.timed_out = Boolean(error.killed);
      throw Error(`${name} ${step.timed_out ? `timed out after ${timeout}ms` : 'failed'}. See the local run logs.\n${log.slice(-1800)}`);
    } finally { step.duration_ms = Date.now() - started; }
  };
  const deviceCommand = (name, args) => command(name, adb, [...(opts.transport === 'wifi' ? ['-s', opts.device] : ['-d']), ...args]);
  const usb = deviceCommand;
  try {
    report.commit = await command('git-head', 'git', ['rev-parse', 'HEAD']);
    report.dirty_tree = Boolean(await command('git-status', 'git', ['status', '--porcelain']));
    // USB remains the default. Wi-Fi is explicit, already paired, local and TLS;
    // this runner never enables legacy tcpip or pairs devices automatically.
    if (opts.transport === 'wifi') pairedWifiTarget(opts.device, await command('wifi-tls-service', adb, ['mdns', 'services']));
    const serialOutput = await usb('device-serial', ['get-serialno']);
    const serial = opts.transport === 'wifi' ? pairedWifiTarget(serialOutput) : physicalUsbSerial(serialOutput);
    if (opts.transport === 'wifi' && serial !== opts.device) throw Error('Wi-Fi target changed.');
    const hardwareSerial = physicalUsbSerial(await usb('device-hardware-serial', ['shell', 'getprop', 'ro.serialno']));
    report.device = { serial, model: await usb('device-model', ['shell', 'getprop', 'ro.product.model']),
      api: await usb('device-api', ['shell', 'getprop', 'ro.build.version.sdk']),
      page_size: await usb('device-page-size', ['shell', 'getconf', 'PAGE_SIZE']), hardware_serial: hardwareSerial };
    if ((await usb('physical-device', ['shell', 'getprop', 'ro.kernel.qemu'])) === '1') throw Error('Emulators are not accepted by this USB runner.');
    report.production_package_present = (await usb('production-package-inventory', ['shell', 'pm', 'list', 'packages', 'com.zalweb.tabby']))
      .split(/\r?\n/).includes('package:com.zalweb.tabby');
    report.flutter = await command('flutter-version', dart, [snapshot, '--version']);
    if (opts.suite === 'preflight') { report.outcome = 'passed'; return; }
    let configFile;
    if (opts.suite === 'live') {
      if (!opts['live-config']) throw Error('Live tests require --live-config .env.usb-live.json.');
      configFile = path.resolve(root, opts['live-config']);
      // Credentials are compiled into a debug APK: keep both input and artifacts private.
      await command('private-config-ignore-check', 'git', ['check-ignore', '--quiet', '--', configFile]);
      const config = validateLiveConfig(JSON.parse(fs.readFileSync(configFile, 'utf8')));
      privateValues = [config.TABBY_TEST_EMAIL, config.TABBY_TEST_PASSWORD, config.SUPABASE_ANON_KEY];
      report.backend_origin = new URL(config.SUPABASE_URL).origin;
    }
    const buildTools = fs.readdirSync(path.join(sdk, 'build-tools')).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
    const aapt = path.join(sdk, 'build-tools', buildTools[0], `aapt${exe}`);
    const targets = opts.suite === 'matrix'
      ? ['integration_test/android_device_matrix_seed_test.dart', 'integration_test/android_device_matrix_test.dart']
      : opts.suite === 'sessions' ? ['integration_test/android_receiving_scope_test.dart', 'integration_test/android_auth_completion_test.dart']
      : opts.suite === 'notifications' ? ['integration_test/android_notification_delivery_test.dart', 'integration_test/android_notification_denied_test.dart']
      : opts.suite === 'live' ? ['integration_test/usb_live_test.dart']
      : opts.suite === 'entry' ? ['integration_test/android_google_entry_test.dart']
      : opts.suite === 'expense-entry' ? ['integration_test/android_expense_entry_test.dart', 'integration_test/android_expense_storage_test.dart']
      : ['integration_test/usb_seed_test.dart', 'integration_test/usb_smoke_test.dart'];
    for (let iteration = 1; iteration <= opts.repeat; iteration++) {
      for (const target of targets) {
        const tag = `${iteration}-${path.basename(target, '.dart')}`;
        const defines = ['--dart-define=TABBY_USB_TEST=true', ...(entryPackage ? ['--dart-define=TABBY_ENTRY_TEST=true'] : []), ...(configFile ? [`--dart-define-from-file=${configFile}`] : [])];
        // Regenerate mode-specific plugin registration after release/native switches.
        await command(`build-${tag}`, dart, [snapshot, 'build', 'apk', '--debug', `--target=${target}`, ...defines], 15 * 60 * 1000);
        const apk = path.join(root, 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk');
        requireTestApk(await command(`verify-package-${tag}`, aapt, ['dump', 'badging', apk]), entryPackage);
        // Recheck hardware identity before every installation, even if an IP is reused.
        if (physicalUsbSerial(await usb(`device-recheck-${tag}`, ['shell', 'getprop', 'ro.serialno'])) !== hardwareSerial) throw Error('Physical device changed during the run.');
        await usb(`install-${tag}`, ['install', '-r', '-t', apk]);
        const denyPermission = target === 'integration_test/android_notification_denied_test.dart';
        if (denyPermission && Number(report.device.api) < 33) throw Error('Native permission-revocation acceptance requires Android API33+.');
        if (Number(report.device.api) >= 33) {
          await usb(`notification-permission-${tag}`, ['shell', 'pm', denyPermission ? 'revoke' : 'grant', deviceTestPackage, 'android.permission.POST_NOTIFICATIONS']);
        }
        try {
          await command(`drive-${tag}`, dart, [snapshot, 'drive', '--no-pub', `--device-id=${serial}`,
            '--driver=test_driver/integration_test.dart', `--target=${target}`, `--use-application-binary=${apk}`, '--keep-app-running', ...defines], 10 * 60 * 1000);
          const driveOutput = fs.readFileSync(path.join(reportDir, `${report.steps.length}-drive-${tag}.log`), 'utf8');
          const caseContract = { sessions: 'android_session_cases.json', notifications: 'android_notification_cases.json', entry: 'android_google_entry_cases.json', 'expense-entry': 'android_expense_entry_cases.json' }[opts.suite];
          const requiredCases = caseContract
            ? JSON.parse(fs.readFileSync(path.join(root, 'integration_test', caseContract), 'utf8'))[path.basename(target)] : [];
          if (caseContract && (!Array.isArray(requiredCases) || requiredCases.length === 0)) throw Error('Missing device case contract.');
          const validation = { name: `validate-drive-${tag}`, outcome: 'failed', required_cases: requiredCases.length };
          report.steps.push(validation);
          validateDriveOutput(driveOutput, requiredCases);
          validation.outcome = 'passed';
        } finally {
          if (denyPermission) await usb(`restore-notification-permission-${tag}`, ['shell', 'pm', 'grant', testPackage, 'android.permission.POST_NOTIFICATIONS']);
        }
        await usb(`stop-${tag}`, ['shell', 'am', 'force-stop', deviceTestPackage]);
      }
    }
    report.outcome = 'passed';
  } catch (error) {
    report.error = redact(error.message);
    process.exitCode = 1;
    process.stderr.write(`${report.error}\n`);
  } finally {
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(path.join(reportDir, 'report.json'), JSON.stringify(report, null, 2));
    process.stdout.write(`Report: ${path.relative(root, path.join(reportDir, 'report.json'))}\n`);
  }
}
module.exports = { physicalUsbSerial, pairedWifiTarget, validateLiveConfig, requireTestApk, validateDriveOutput, options };
if (require.main === module) main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
