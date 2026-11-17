'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {test} = require('node:test');

const directory = path.join(__dirname, '..', '.github', 'workflows');
const read = name => fs.readFileSync(path.join(directory, name), 'utf8').replace(/\r\n/g, '\n');

test('coordinated mobile builds produce private platform artifacts', () => {
  const mobile = read('build-mobile.yml');
  assert(mobile.includes('workflow_dispatch:'));
  assert(mobile.includes('branches:\n      - main'));
  assert(mobile.includes("tags:\n      - 'v*'"));
  for (const platform of ['android', 'ios']) {
    const build = read(`build-${platform}.yml`);
    assert(mobile.includes(`./.github/workflows/build-${platform}.yml`));
    assert(build.includes('workflow_call:'));
    assert(build.includes('contents: read'));
    assert(build.includes('actions/upload-artifact@v4'));
    assert(!build.includes('contents: write'));
    assert(!build.includes('softprops/action-gh-release'));
  }
  assert(mobile.includes('secrets: inherit'));
});

test('Android build requires signing and verifies the candidate before upload', () => {
  const android = read('build-android.yml');
  assert(android.includes('All Android release builds require signing secrets.'));
  assert(android.includes('flutter build apk --release'));
  assert(android.includes('ANDROID_RELEASE_CERT_SHA256: ${{ vars.ANDROID_RELEASE_CERT_SHA256 }}'));
  assert(android.indexOf('verify-android-artifact.cjs') < android.indexOf('actions/upload-artifact@v4'));
  assert(android.includes('output/candidate-manifest.json'));
  assert(android.includes('if-no-files-found: error'));
});

test('unsigned iOS packaging stays private and cannot enter the Android publisher', () => {
  const ios = read('build-ios.yml');
  assert(ios.includes('flutter build ipa --no-codesign --release'));
  assert(ios.includes('path: output/Tabby.ipa'));
  assert(!ios.includes('contents: write'));
  const publisher = read('publish-latest-build.yml');
  assert(publisher.includes('name: Tabby-android-candidate'));
  assert(!publisher.includes('candidate/Tabby.ipa'));
});

test('only explicit main-branch publication can consume an approved exact candidate', () => {
  const manual = read('publish-release-apk.yml');
  assert(manual.includes('workflow_dispatch:'));
  assert(!/\b(?:workflow_run|push|pull_request):/.test(manual));
  assert(manual.includes('uses: ./.github/workflows/publish-latest-build.yml'));
  const publisher = read('publish-latest-build.yml');
  assert(publisher.includes('workflow_call:'));
  assert(!/\b(?:workflow_run|workflow_dispatch|push|pull_request):/.test(publisher));
  for (const input of ['run_id', 'candidate_commit']) {
    assert(manual.includes(`${input}:`));
    assert(publisher.includes(`${input}:`));
    assert(manual.includes(input + ': ${{ inputs.' + input + ' }}'));
  }
  for (const workflow of [manual, publisher]) {
    assert(workflow.includes("github.ref == 'refs/heads/main'"));
  }
  assert(publisher.includes('environment: android-release'));
  assert(publisher.includes("run.conclusion !== 'success' || run.head_sha !== commit"));
  assert(publisher.includes("run.path !== '.github/workflows/build-mobile.yml'"));
  const publishIndex = publisher.indexOf('softprops/action-gh-release@v2');
  for (const gate of ['verify-android-artifact.cjs', 'check-release-gate.cjs', 'cmp candidate/candidate-manifest.json']) {
    const gateIndex = publisher.indexOf(gate);
    assert(gateIndex >= 0 && gateIndex < publishIndex, gate);
  }
  assert(publisher.includes('target_commitish: ${{ inputs.candidate_commit }}'));
  assert(publisher.includes('overwrite_files: false'));
  const publishers = fs.readdirSync(directory).filter(name => name.endsWith('.yml') && read(name).includes('softprops/action-gh-release'));
  assert.deepEqual(publishers, ['publish-latest-build.yml']);
});
