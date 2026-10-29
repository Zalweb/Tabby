const fs = require('fs');
const path = require('path');
const assert = require('assert');

const readText = file => fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');

const repoRoot = path.join(__dirname, '..');
const androidWorkflow = readText(
  path.join(repoRoot, '.github', 'workflows', 'build-android.yml')
);
const iosWorkflow = readText(
  path.join(repoRoot, '.github', 'workflows', 'build-ios.yml')
);
const mobileWorkflow = readText(
  path.join(repoRoot, '.github', 'workflows', 'build-mobile.yml')
);
const publisherPath = path.join(
  repoRoot,
  '.github',
  'workflows',
  'publish-latest-build.yml'
);

assert(androidWorkflow.includes('workflow_call:'),
  'Android workflow must be reusable by the coordinated mobile build');
assert(iosWorkflow.includes('workflow_call:'),
  'iOS workflow must be reusable by the coordinated mobile build');
assert(mobileWorkflow.includes('workflow_dispatch:') &&
       mobileWorkflow.includes("branches:\n      - main") &&
       mobileWorkflow.includes("tags:\n      - 'v*'"),
  'Coordinated mobile build must support manual, main, and release-tag triggers');
assert(mobileWorkflow.includes('./.github/workflows/build-android.yml') &&
       mobileWorkflow.includes('./.github/workflows/build-ios.yml') &&
       mobileWorkflow.includes('secrets: inherit'),
  'Coordinated mobile build must invoke both platform workflows with secrets');
assert(fs.existsSync(publisherPath),
  'A coordinated latest-build publisher workflow must exist');

const publisher = readText(publisherPath);
assert(publisher.includes('workflow_run:'),
  'Latest-build publisher must run after build workflows complete');
assert(publisher.includes('Build Android APK + iOS IPA'),
  'Publisher must wait for the coordinated mobile build workflow');
assert(publisher.includes('actions: read') && publisher.includes('contents: write'),
  'Publisher must read build artifacts and write the public release');
assert(publisher.includes('head_sha'),
  'Publisher must pair APK and IPA runs by commit SHA');
assert(publisher.includes('actions/download-artifact@v4'),
  'Publisher must download artifacts from the successful build runs');
assert(publisher.includes('actions/checkout@v4') && publisher.includes('pubspec.yaml'),
  'Publisher must read the app version from the built commit');
assert(publisher.includes('APP_VERSION') && publisher.includes('RELEASE_TAG'),
  'Publisher must derive a release version and tag from pubspec.yaml');
assert(publisher.includes('Tabby-v${APP_VERSION}.apk') &&
       publisher.includes('Tabby-v${APP_VERSION}.ipa'),
  'Publisher must expose versioned APK and IPA asset names');
assert(publisher.includes('Tabby.apk') && publisher.includes('Tabby.ipa'),
  'Publisher must retain compatibility aliases for older website links');
assert(publisher.includes('tag_name: ${{ steps.resolve.outputs.release_tag }}'),
  'Publisher must publish under the semantic version release tag');
assert(publisher.includes('overwrite_files: true') && publisher.includes('make_latest: true'),
  'Publisher must replace the newest public release assets');

for (const relativePath of ['docs/app.js', 'landing/app.js']) {
  const appJs = readText(path.join(repoRoot, relativePath));
  assert(appJs.includes('/releases/latest'),
    `${relativePath} must resolve downloads from the latest public release`);
  assert(appJs.includes('releases/latest/download/Tabby.apk'),
    `${relativePath} must retain the canonical APK fallback link`);
}

console.log('Release workflow contract verification passed.');
