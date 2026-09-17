const fs = require('fs');
const path = require('path');
const assert = require('assert');

const repoRoot = path.join(__dirname, '..');
const androidWorkflow = fs.readFileSync(
  path.join(repoRoot, '.github', 'workflows', 'build-android.yml'),
  'utf8'
);
const iosWorkflow = fs.readFileSync(
  path.join(repoRoot, '.github', 'workflows', 'build-ios.yml'),
  'utf8'
);
const publisherPath = path.join(
  repoRoot,
  '.github',
  'workflows',
  'publish-latest-build.yml'
);

assert(androidWorkflow.includes("branches:\n      - main"),
  'Android builds must run automatically when main changes');
assert(iosWorkflow.includes("branches:\n      - main"),
  'iOS builds must run automatically when main changes');
assert(fs.existsSync(publisherPath),
  'A coordinated latest-build publisher workflow must exist');

const publisher = fs.readFileSync(publisherPath, 'utf8');
assert(publisher.includes('workflow_run:'),
  'Latest-build publisher must run after build workflows complete');
assert(publisher.includes('Build Android APK') && publisher.includes('Build iOS IPA'),
  'Publisher must wait for both platform build workflows');
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
  const appJs = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  assert(appJs.includes('/releases/latest'),
    `${relativePath} must resolve downloads from the latest public release`);
  assert(appJs.includes('releases/latest/download/Tabby.apk'),
    `${relativePath} must retain the canonical APK fallback link`);
}

console.log('Release workflow contract verification passed.');
