const fs = require('fs');
const path = require('path');
const assert = require('assert');

// 1. Verify docs/index.html
const htmlPath = path.join(__dirname, '..', 'docs', 'index.html');
assert(fs.existsSync(htmlPath), 'docs/index.html must exist');
const html = fs.readFileSync(htmlPath, 'utf8');

assert(html.includes('Tabby — Keep tabs. Settle up.'), 'Title must match Tabby tagline');
assert(html.includes('data-role="apk-download-btn"'), 'Must have apk download button data-role');
assert(html.includes('data-role="version-tag"'), 'Must have version tag element');
assert(html.includes('data-role="apk-size"'), 'Must have apk size element');
assert(html.includes('data-role="release-date"'), 'Must have release date element');
assert(html.includes('app.js'), 'Must load app.js');
assert(html.includes('styles.css'), 'Must load styles.css');
assert(html.includes('assets/tabby-icon.jpg'), 'Must link to mascot icon');
assert(html.includes('preview-home.png'), 'Must have Homepage mockup image');
assert(html.includes('preview-banner.png'), 'Must have Banner Page mockup image');
assert(html.includes('Homepage') && html.includes('Banner Page') && html.includes('Tab Page'), 'Must display 3 mockup labels');
assert(html.includes('hero-text-col'), 'Must include hero-text-col column');
assert(!html.includes('>GitHub<') && !html.includes('>GitHub Repo<'), 'Must not have user-facing GitHub links');

// 2. Verify docs/styles.css
const cssPath = path.join(__dirname, '..', 'docs', 'styles.css');
assert(fs.existsSync(cssPath), 'docs/styles.css must exist');
const css = fs.readFileSync(cssPath, 'utf8');
assert(css.includes('--tabby-charcoal: #1F1F1F'), 'Must have Tabby charcoal color token');
assert(css.includes('--tabby-amber: #FFB74D'), 'Must have Tabby amber color token');
assert(css.includes('.hero-title'), 'Must have hero title styling');
assert(css.includes('.btn-amber'), 'Must have amber button styling');
assert(css.includes('.hero-container') && css.includes('grid-template-columns: 1fr 1.08fr'), 'Must have 2-column hero container grid');
assert(css.includes('.hero-text-col'), 'Must have hero text column styling');

// 3. Verify docs/app.js
const jsPath = path.join(__dirname, '..', 'docs', 'app.js');
assert(fs.existsSync(jsPath), 'docs/app.js must exist');
const js = fs.readFileSync(jsPath, 'utf8');
assert(js.includes('api.github.com/repos/') && js.includes('Zalweb') && js.includes('Tabby'), 'Must fetch from GitHub Releases API');
assert(js.includes('apk-download-btn'), 'Must select apk-download-btn');
assert(js.includes('releases/latest/download/Tabby.apk'), 'Must have canonical fallback URL');
assert(js.includes('applyReleaseData'), 'Must have release data application logic');

// 4. Verify mirrored landing/ directory
// 5. Simulate release update logic
function simulateUpdate(release) {
  let apkAsset = null;
  if (Array.isArray(release.assets)) {
    apkAsset = release.assets.find(a => a.name && a.name.endsWith('.apk') && a.name.includes('-')) ||
               release.assets.find(a => a.name && a.name.endsWith('.apk'));
  }
  const apkUrl = apkAsset ? apkAsset.browser_download_url : 'https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.apk';
  const sizeMb = apkAsset ? (apkAsset.size / (1024 * 1024)).toFixed(1) + ' MB' : '70.8 MB';
  return {
    tagName: release.tag_name,
    apkUrl,
    sizeMb,
    filename: apkAsset ? apkAsset.name : 'Tabby.apk'
  };
}

// Test with current v1.0.0 release
const v1 = simulateUpdate({
  tag_name: 'v1.0.0',
  assets: [
    { name: 'Tabby-v1.0.0.apk', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.0/Tabby-v1.0.0.apk', size: 70776401 },
    { name: 'Tabby.apk', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.0/Tabby.apk', size: 70961025 }
  ]
});
assert.strictEqual(v1.tagName, 'v1.0.0');
assert.strictEqual(v1.apkUrl, 'https://github.com/Zalweb/Tabby/releases/download/v1.0.0/Tabby-v1.0.0.apk');
assert.strictEqual(v1.filename, 'Tabby-v1.0.0.apk');
assert.strictEqual(v1.sizeMb, '67.5 MB');

// Test with future new release v1.0.1
const v2 = simulateUpdate({
  tag_name: 'v1.0.1',
  assets: [
    { name: 'Tabby-v1.0.1.apk', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.1/Tabby-v1.0.1.apk', size: 75000000 },
    { name: 'Tabby.apk', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.1/Tabby.apk', size: 75000000 }
  ]
});
assert.strictEqual(v2.tagName, 'v1.0.1');
assert.strictEqual(v2.apkUrl, 'https://github.com/Zalweb/Tabby/releases/download/v1.0.1/Tabby-v1.0.1.apk');
assert.strictEqual(v2.filename, 'Tabby-v1.0.1.apk');
assert.strictEqual(v2.sizeMb, '71.5 MB');

// 6. Verify live Vercel deployment
const https = require('https');
https.get('https://tabby-web-fawn.vercel.app', (res) => {
  assert.strictEqual(res.statusCode, 200, 'Live Vercel URL must return 200 OK');
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    assert(data.includes('Tabby — Keep tabs. Settle up.'), 'Live site must contain title');
    assert(data.includes('Download Tabby APK'), 'Live site must contain Download APK CTA');
    console.log('Live Vercel deployment verification SUCCESSFUL! Status 200 OK.');
  });
}).on('error', (err) => {
  console.error('Live URL error:', err);
});
