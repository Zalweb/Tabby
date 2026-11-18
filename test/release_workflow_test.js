'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const childProcess = require('node:child_process');
const {test} = require('node:test');

const root = path.join(__dirname, '..');
const workflows = path.join(root, '.github', 'workflows');
const read = name => fs.readFileSync(path.join(workflows, name), 'utf8').replace(/\r\n/g, '\n');
const release = require(path.join(root, 'scripts', 'mobile-release.cjs'));

test('coordinated main builds create private platform artifacts with one shared version', () => {
  const mobile = read('build-mobile.yml');
  assert(mobile.includes('workflow_dispatch:'));
  assert(mobile.includes('branches:\n      - main'));
  assert(mobile.includes("tags:\n      - 'v*'"));
  assert(mobile.includes("source_mode: ${{ github.ref == 'refs/heads/main' && 'current' || 'frozen' }}"));
  for (const platform of ['android', 'ios']) {
    const build = read(`build-${platform}.yml`);
    assert(mobile.includes(`./.github/workflows/build-${platform}.yml`));
    assert(build.includes('workflow_call:'));
    assert(build.includes('contents: read'));
    assert(build.includes('actions/upload-artifact@v4'));
    assert(!build.includes('contents: write'));
    assert(!build.includes('softprops/action-gh-release'));
  }
  const android = read('build-android.yml');
  assert(android.includes('flutter build apk --release'));
  assert(android.includes('output/Tabby.apk'));
  const ios = read('build-ios.yml');
  assert(ios.includes('--verify-current-source'));
  assert(ios.includes('--verify-source'));
  assert(ios.includes('--require-pubspec-version'));
  assert(ios.includes('output/Tabby.ipa'));
  assert(ios.includes('Tabby-ios-sideload-${{ github.run_number }}'));
  assert(ios.includes('--record-current'));
  const iosPackage = fs.readFileSync(path.join(root, 'scripts', 'ios-package.py'), 'utf8');
  assert(iosPackage.includes('output.with_suffix(output.suffix + ".json")'));
  const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
  assert.match(pubspec, /^version: 1\.0\.4\+25$/m, 'Shared next build number must exceed published +24');
});

test('Android candidate build remains release-signed, verified and private', () => {
  const android = read('build-android.yml');
  assert(android.includes('All Android release builds require signing secrets.'));
  assert(android.includes('ANDROID_RELEASE_CERT_SHA256: ${{ vars.ANDROID_RELEASE_CERT_SHA256 }}'));
  assert(android.indexOf('verify-android-artifact.cjs') < android.indexOf('actions/upload-artifact@v4'));
  assert(android.includes('output/candidate-manifest.json'));
  assert(android.includes('if-no-files-found: error'));
  assert(!android.includes('contents: write'));
});

test('iOS CI ties tracked source and simulator evidence to the exact build commit', () => {
  const ios = read('build-ios.yml');
  assert(ios.includes('--verify-current-source'));
  assert(ios.includes('--expected-commit "$GITHUB_SHA"'));
  assert(ios.includes('IOS_SOURCE_MANIFEST=$source_manifest'));
  assert(ios.includes('--source-manifest "$IOS_SOURCE_MANIFEST"'));
  assert(ios.includes('--record-current --source-manifest "$IOS_SOURCE_MANIFEST"'));
  assert(ios.includes('TABBY_BUILD_NUMBER=${resolved_version##*+}'));
  assert(ios.includes('flutter build ipa --no-codesign --release'));
  assert(!ios.includes('version 23'));
});

test('paired release reconciliation is automatic, fail-closed and reviewer-gated', () => {
  const publisher = read('publish-latest-build.yml');
  assert(publisher.includes('workflow_run:'));
  assert(publisher.includes('workflows:\n      - Build Android APK + iOS IPA'));
  assert(publisher.includes('schedule:'));
  assert(publisher.includes('docs/releases/**'));
  assert(publisher.includes('docs/progress/tasks/**'));
  assert(!/\n  workflow_dispatch:/.test(publisher), 'Routine publication has no manual dispatch entry');
  const releaseHelper = fs.readFileSync(path.join(root, 'scripts', 'mobile-release.cjs'), 'utf8');
  assert(releaseHelper.includes("workflow_id: 'build-mobile.yml'"));
  assert(releaseHelper.includes("'docs', 'releases'"));
  assert(publisher.includes('selectBuildRun'));
  assert(publisher.includes('EXPECTED_RUN_ID'));
  assert(publisher.includes('ref: main'));
  assert(publisher.includes('check-release-gate.cjs'));
  assert(publisher.includes('verify-android-artifact.cjs'));
  assert(publisher.includes('verify-ios-artifact.py'));
  assert(publisher.includes('cmp candidate/candidate-manifest.json candidate/rechecked.json'));
  const iosBuild = read('build-ios.yml');
  assert(iosBuild.includes('Tabby-ios-sideload-${{ github.run_number }}'));
  assert(releaseHelper.includes('Tabby-ios-sideload-${run.run_number}'));
  assert(publisher.includes('environment: android-release'));

  const environment = publisher.indexOf('environment: android-release');
  const firstGate = publisher.indexOf('check-release-gate.cjs');
  assert(firstGate >= 0 && firstGate < environment, 'Evidence is checked before requesting release approval');
  assert(publisher.includes('draft: true'));
  assert(publisher.includes('make_latest: false'));
  assert(publisher.includes('candidate/Tabby.apk\n            ios-candidate/Tabby.ipa'));
  assert(publisher.includes("make_latest: 'true'"));
  assert(publisher.indexOf('Verify both uploaded asset digests') < publisher.indexOf('Publish the complete pair as latest'));
  assert(publisher.includes('release.verifyTagTarget'));
  assert.equal((publisher.match(/git fetch --force origin '\+refs\/tags\/\*:refs\/tags\/\*'/g) || []).length, 2,
    'Both trusted main checkouts fetch all origin tags before target verification');
  assert(!publisher.includes('hashFiles('), 'Raw artifact SHA-256 must not use Actions hashFiles()');
  assert(publisher.includes("crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')"));
  assert(publisher.includes("digest('candidate/Tabby.apk')"));
  assert(publisher.includes("digest('ios-candidate/Tabby.ipa')"));
  assert(publisher.includes('No successful main build has matching reviewed release evidence; skipping publication.'));
  assert(publisher.includes("!tagTarget && draft.target_commitish?.toLowerCase()"));

  const publishers = fs.readdirSync(workflows).filter(name => name.endsWith('.yml') && read(name).includes('softprops/action-gh-release'));
  assert.deepEqual(publishers, ['publish-latest-build.yml']);
});

test('newer unreviewed successful pushes do not shadow an older evidence-backed candidate', async () => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'tabby-release-selection-'));
  const olderSha = 'a'.repeat(40);
  const newerSha = 'b'.repeat(40);
  const evidenceDirectory = path.join(fixtureRoot, 'docs', 'releases');
  fs.mkdirSync(evidenceDirectory, {recursive: true});
  fs.writeFileSync(path.join(evidenceDirectory, `${olderSha}.json`), '{}');
  const run = (id, runNumber, sha) => ({
    id,
    run_number: runNumber,
    status: 'completed',
    conclusion: 'success',
    path: '.github/workflows/build-mobile.yml',
    head_branch: 'main',
    head_repository: {full_name: 'Zalweb/Tabby'},
    head_sha: sha,
    event: 'push',
  });
  const runs = [run(102, 102, newerSha), run(101, 101, olderSha)];
  const github = {
    rest: {actions: {listWorkflowRuns: async () => ({data: {workflow_runs: runs}})}},
    paginate: async (_endpoint, query) => {
      assert.equal(query.workflow_id, 'build-mobile.yml');
      assert.equal(query.branch, 'main');
      return [...runs];
    },
  };
  const context = {repo: {owner: 'Zalweb', repo: 'Tabby'}, eventName: 'schedule'};
  try {
    const selected = await release.selectBuildRun({github, context, env: {}, root: fixtureRoot});
    assert.equal(selected.run_id, '101');
    assert.equal(selected.commit, olderSha);

    fs.unlinkSync(path.join(evidenceDirectory, `${olderSha}.json`));
    assert.equal(await release.selectBuildRun({github, context, env: {}, root: fixtureRoot}), null,
      'No reviewed evidence is a clean no-publish result');
  } finally {
    fs.rmSync(fixtureRoot, {recursive: true, force: true});
  }
});

test('existing tags are checked by their actual refs, independent of target_commitish metadata', () => {
  const execFileSync = childProcess.execFileSync;
  const tag = 'v1.0.4+25';
  const commit = 'c'.repeat(40);
  let resolved = commit;
  const calls = [];
  childProcess.execFileSync = (_command, args) => {
    calls.push(args);
    if (args[0] === 'tag') return `${tag}\n`;
    if (args[0] === 'rev-parse') return `${resolved}\n`;
    throw new Error(`Unexpected git call: ${args.join(' ')}`);
  };
  try {
    assert.equal(release.verifyTagTarget('.', tag, commit), commit);
    assert.deepEqual(calls[1], ['rev-parse', '--verify', `refs/tags/${tag}^{commit}`]);
    resolved = 'd'.repeat(40);
    assert.throws(() => release.verifyTagTarget('.', tag, commit), /different commit/);
  } finally {
    childProcess.execFileSync = execFileSync;
  }

  const candidate = {
    commit,
    tag,
    version_name: '1.0.4',
    version_code: 25,
    apk_sha256: '1'.repeat(64),
    ipa_sha256: '2'.repeat(64),
  };
  const draft = {tag_name: tag, target_commitish: 'main', draft: true, id: 1};
  assert.equal(release.planRelease(candidate, [draft], null, commit).action, 'resume-draft');
  assert.throws(() => release.planRelease(candidate, [draft], null), /different source commit/);
});

test('manual recovery routes through the same guarded paired publisher', () => {
  const manual = read('publish-release-apk.yml');
  assert(manual.includes('workflow_dispatch:'));
  assert(manual.includes('uses: ./.github/workflows/publish-latest-build.yml'));
  for (const input of ['run_id', 'candidate_commit']) {
    assert(manual.includes(`${input}:`));
    assert(manual.includes(input + ': ${{ inputs.' + input + ' }}'));
  }
  assert(manual.includes("github.ref == 'refs/heads/main'"));
  assert(!read('publish-latest-build.yml').includes('softprops/action-gh-release@v2'));
});
