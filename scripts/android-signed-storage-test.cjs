#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const runFile = promisify(execFile);
const {require16kbEmulator} = require('./android-emulator-test.cjs');
const {verifyArtifact, requireHex} = require('./verify-android-artifact.cjs');
const root = path.resolve(__dirname, '..');
const packageName = 'com.zalweb.tabby';

function options(args) {
  const opts = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--device', '--baseline-apk', '--public-config', '--expected-cert'].includes(args[i]) || !args[i + 1]) throw Error('Explicit emulator, signed baseline APK, public-client config and expected certificate required.');
    opts[args[i].slice(2)] = args[i + 1];
  }
  if (!/^emulator-\d+$/.test(opts.device || '') || !opts['baseline-apk'] || !opts['public-config']) throw Error('Only an explicit isolated emulator and baseline are allowed.');
  requireHex(opts['expected-cert'], 64, 'Expected private production certificate');
  return opts;
}

function requirePublicConfig(config) {
  const allowed = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'FIREBASE_APP_ID', 'FIREBASE_API_KEY', 'FIREBASE_PROJECT_ID', 'FIREBASE_SENDER_ID'];
  if (Object.keys(config).some(k => !allowed.includes(k)) || typeof config.SUPABASE_URL !== 'string' || new URL(config.SUPABASE_URL).protocol !== 'https:') throw Error('Only public client identifiers are allowed in the restoration build.');
  let payload;
  try { payload = JSON.parse(Buffer.from(config.SUPABASE_ANON_KEY.split('.')[1], 'base64url')); } catch { throw Error('Expected public anon client credential.'); }
  if (payload.role !== 'anon') throw Error('Privileged credentials are forbidden in APK defines.');
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
  const java = process.env.JAVA_HOME ? path.join(process.env.JAVA_HOME, 'bin', 'java' + exe) : 'java';
  const baseline = path.resolve(root, opts['baseline-apk']);
  const publicConfig = path.resolve(root, opts['public-config']);
  requirePublicConfig(JSON.parse(fs.readFileSync(publicConfig, 'utf8').replace(/^\uFEFF/, '')));
  const dir = path.join(root, '.dart_tool/signed-storage-tests', new Date().toISOString().replace(/[:.]/g, '-'));
  fs.mkdirSync(dir, {recursive: true});
  const report = {started_at: new Date().toISOString(), outcome: 'failed', device: opts.device, package: packageName, steps: [], artifacts: [], limits: ['Owned x86_64 16KB emulator and new production key only; no legacy debug-key upgrade or remote financial action.', 'Synthetic encrypted storage payloads, not backend replay or every M1 journey.']};
  const digest = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
  const command = async (name, file, args, timeout = 60000) => {
    const step = {name, outcome: 'failed'}; report.steps.push(step);
    process.stdout.write(name + '\n');
    try {
      const r = await runFile(file, args, {cwd: root, windowsHide: true, timeout, maxBuffer: 16 * 1024 * 1024});
      fs.writeFileSync(path.join(dir, report.steps.length + '-' + name + '.log'), r.stdout + r.stderr);
      step.outcome = 'passed'; return (r.stdout + r.stderr).trim();
    } catch (e) {
      fs.writeFileSync(path.join(dir, report.steps.length + '-' + name + '.log'), (e.stdout || '') + (e.stderr || ''));
      throw Error(name + ' failed; inspect ignored local log.');
    }
  };
  const device = (name, args, timeout) => command(name, adb, ['-s', opts.device, ...args], timeout);
  const environment = async () => require16kbEmulator(await device('qemu', ['shell', 'getprop', 'ro.kernel.qemu']), await device('pages', ['shell', 'getconf', 'PAGE_SIZE']), await device('abi', ['shell', 'getprop', 'ro.product.cpu.abi']));
  const packageIdentity = async () => {
    const dump = await device('package-identity', ['shell', 'dumpsys', 'package', packageName]);
    const version = Number(dump.match(/versionCode=(\d+)/)?.[1]);
    const appId = dump.match(/\b(?:appId|userId)=(\d+)/)?.[1];
    if (!Number.isSafeInteger(version) || !appId) throw Error('Cannot establish baseline package identity.');
    return {version, appId};
  };
  const check = apk => verifyArtifact({apk, sdk, java, expectedCert: opts['expected-cert'], commit: report.commit});
  let installedFixture = false, restoration, initial;
  const install = async artifact => {
    await environment();
    if (digest(artifact.path) !== artifact.manifest.apk_sha256) throw Error('Verified APK bytes changed before install.');
    await device('install-' + artifact.phase, ['install', '-r', artifact.path], 120000);
    const now = await packageIdentity();
    if (now.version !== artifact.manifest.version_code || now.appId !== initial.appId) throw Error('Package identity/version changed unexpectedly.');
    await device('stop-' + artifact.phase, ['shell', 'am', 'force-stop', packageName]);
    await device('launch-' + artifact.phase, ['shell', 'am', 'start', '-W', '-n', packageName + '/.MainActivity']);
  };
  try {
    report.commit = await command('git-head', 'git', ['rev-parse', 'HEAD']);
    report.dirty_tree = Boolean(await command('git-status', 'git', ['status', '--porcelain']));
    await environment();
    const original = check(baseline);
    initial = await packageIdentity();
    if (initial.version !== original.version_code) throw Error('Installed baseline version differs from supplied signed APK.');
    const remote = await device('baseline-path', ['shell', 'pm', 'path', packageName]);
    if (!/^package:\/data\/app\/[^\r\n]+\/base\.apk$/.test(remote)) throw Error('Expected exactly one baseline base APK.');
    const pulled = path.join(dir, 'installed-baseline.apk');
    await device('pull-owned-baseline', ['pull', remote.slice(8), pulled]);
    if (digest(pulled) !== original.apk_sha256) throw Error('Emulator does not contain the exact private signed baseline; refusing to replace it.');
    report.baseline = {version_code: initial.version, apk_sha256: original.apk_sha256, app_id: initial.appId};
    // Prepare and validate the real-main recovery APK before replacing anything.
    for (const [phase, offset] of [['restore', 3], ['seed', 1], ['verify', 2]]) {
      const version = initial.version + offset;
      const fixture = phase !== 'restore';
      await command('build-' + phase, dart, [snapshot, 'build', 'apk', '--release', '--build-number=' + version, '--target=' + (fixture ? 'integration_test/android_signed_storage_fixture.dart' : 'lib/main.dart'), ...(fixture ? ['--dart-define=TABBY_SIGNED_STORAGE_FIXTURE=' + phase] : ['--dart-define-from-file=' + publicConfig])], 15 * 60000);
      const apk = path.join(dir, phase + '.apk');
      fs.copyFileSync(path.join(root, 'build/app/outputs/flutter-apk/app-release.apk'), apk);
      const manifest = check(apk);
      if (manifest.application_id !== packageName || manifest.version_code !== version) throw Error('Unexpected built package/version.');
      const artifact = {phase, path: apk, manifest};
      report.artifacts.push({phase, ...manifest});
      if (phase === 'restore') restoration = artifact;
      else {
        // Defer installations until all three signed artifacts are prepared.
        if (phase === 'seed') report.seed_artifact = artifact;
        else report.verify_artifact = artifact;
      }
    }
    for (const artifact of [report.seed_artifact, report.verify_artifact]) {
      installedFixture = true; // Also restores after a partially successful install.
      await install(artifact);
      const pid = await device('pid-' + artifact.phase, ['shell', 'pidof', packageName]);
      if (!/^\d+$/.test(pid)) throw Error('Unexpected release fixture PID.');
      const expected = 'SIGNED_STORAGE phase=' + artifact.phase + ' passed=true historyEntries=10000 durableOperation=true draft=true pin=true sameKey=true ownerIsolated=true';
      const deadline = Date.now() + 120000; let accepted = false;
      while (Date.now() < deadline) {
        const output = await device('proof-' + artifact.phase, ['logcat', '-d', '--pid=' + pid, '-s', 'flutter:I']);
        if (output.includes('SIGNED_STORAGE phase=' + artifact.phase + ' passed=false')) throw Error('Actual release fixture rejected stored state.');
        if (output.includes(expected)) {accepted = true; break;}
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      if (!accepted) throw Error('Release storage proof timed out.');
      report[artifact.phase + '_storage_verified'] = true;
    }
    report.outcome = 'passed';
  } catch (e) { report.error = e.message; process.exitCode = 1; process.stderr.write(e.message + '\n'); }
  finally {
    if (installedFixture && restoration) {
      try { await install(restoration); report.real_main_restored = true; }
      catch (e) { report.restoration_error = e.message; report.outcome = 'failed'; process.exitCode = 1; }
    }
    delete report.seed_artifact; delete report.verify_artifact;
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    process.stdout.write('Report: ' + path.relative(root, path.join(dir, 'report.json')) + '\n');
  }
}
module.exports = {options, requirePublicConfig};
if (require.main === module) main().catch(() => {process.stderr.write('Signed storage preflight failed.\n');process.exitCode = 1;});
