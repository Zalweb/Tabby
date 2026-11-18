const fs = require('fs');
const path = require('path');
const assert = require('assert');

console.log('--- Starting Tabby Web Landing Page Verification Suite ---');

const root = path.join(__dirname, '..');
const landingDir = path.join(root, 'landing');
const docsDir = path.join(root, 'docs');

// 1. Verify docs/index.html structure and product-accurate content
const htmlPath = path.join(docsDir, 'index.html');
assert(fs.existsSync(htmlPath), 'docs/index.html must exist');
const html = fs.readFileSync(htmlPath, 'utf8');

assert(html.includes('Tabby — Keep tabs. Settle up.'), 'Title must match Tabby tagline');
assert(html.includes('One running tab per friendship'), 'Hero must describe the one-tab-per-friendship model');
assert(html.includes('GCash, Maya, or QR Ph'), 'Hero must mention supported settlement rails');
assert(html.includes('No money held by Tabby'), 'Hero must state that Tabby never holds funds');
assert(html.includes('id="features"') && html.includes('id="screens"') && html.includes('id="why-tabby"'), 'Must have features, screens, and why-tabby sections');
assert(html.includes('id="how-it-works"') && html.includes('id="download"') && html.includes('id="faq"'), 'Must have how-it-works, download, and FAQ sections');

assert(html.includes('data-role="apk-download-btn"'), 'Must have APK download buttons');
assert(html.includes('data-role="ipa-download-btn"'), 'Must have IPA download buttons');
assert(html.includes('data-role="version-tag"'), 'Must have version tag elements');
assert(html.includes('data-role="release-date"'), 'Must have release date elements');
assert(html.includes('data-role="apk-size"'), 'Must have APK size elements');
assert(html.includes('data-role="ipa-size"'), 'Must have IPA size elements');
assert(html.includes('data-role="apk-filename"'), 'Must have APK filename element');
assert(html.includes('data-role="live-status"'), 'Must have live release status elements');
assert(html.includes('data-role="changelog-body"'), 'Must have a changelog body target');
assert(html.includes('data-nav-toggle'), 'Must have a mobile navigation toggle');
assert(html.includes('app.js') && html.includes('styles.css'), 'Must load app.js and styles.css');

assert(html.includes('assets/tabby-launcher.png'), 'Must use the current launcher icon');
assert(html.includes('assets/mascot-welcome.png') && html.includes('assets/mascot-notebook.png'), 'Must use the welcome and notebook mascot artwork');
assert(html.includes('assets/mascot-thinking.png') && html.includes('assets/mascot-celebrating.png') && html.includes('assets/mascot-reminder.png'), 'Must use situation mascot artwork');
assert(html.includes('assets/screens/home-light.png') && html.includes('assets/screens/home-dark.png'), 'Must show current light and dark home screenshots');
assert(html.includes('assets/screens/login-light.png') && html.includes('assets/screens/detail-light.png'), 'Must show welcome and tab detail screenshots');
assert(!html.includes('preview-home.png') && !html.includes('preview-banner.png'), 'Must not reference outdated app screenshots');
assert(!html.includes('tabby-icon.jpg'), 'Must not reference the legacy icon asset');

assert(html.includes('One tab per friendship'), 'Feature cards must describe one tab per friendship');
assert(html.includes('Custom amounts'), 'Feature cards must describe custom split amounts');
assert(html.includes('Centavo-exact'), 'Feature cards must describe centavo-exact math');
assert(html.includes('Recipient confirmed') && html.includes('recipient confirms'), 'Must describe recipient-confirmed payments');
assert(html.includes('Append-only history'), 'Must describe append-only ledger history');
assert(html.includes('Offline-durable'), 'Must describe durable offline behavior');
assert(html.includes('Encrypted at rest'), 'Must describe encrypted payment fields');
assert(html.includes('Group tabs'), 'Must describe group tabs');
assert(html.includes('Works at the table — even with no signal.'), 'Must include the offline feature panel');
assert(html.includes('Good to know before you split.'), 'Must include the FAQ section');
assert(html.includes('Privacy Policy') && html.includes('Terms of Service'), 'Must link the legal pages');

const forbiddenGitHubLabels = ['>GitHub<', '>GitHub Repo<'];
for (const label of forbiddenGitHubLabels) {
  assert(!html.includes(label), `Must not have a user-facing ${label} link label`);
}

const emojiRegex = /[\uD800-\uDBFF][\uDC00-\uDFFF]|[\u2600-\u27BF]/g;
const htmlEmojiMatches = html.match(emojiRegex) || [];
assert.strictEqual(htmlEmojiMatches.length, 0, `HTML must not contain emojis. Found: ${htmlEmojiMatches.join(' ')}`);

assert((html.match(/<details class="faq-card/g) || []).length >= 6, 'Must include at least six FAQ cards');
assert(html.includes('<details class="changelog">'), 'Changelog must work without JavaScript');
assert(html.includes('name="viewport"') && html.includes('meta name="description"'), 'Must include responsive viewport and meta description');

console.log('✓ docs/index.html structure, content, and asset references verified');

// 2. Verify docs/styles.css design system
const cssPath = path.join(docsDir, 'styles.css');
assert(fs.existsSync(cssPath), 'docs/styles.css must exist');
const css = fs.readFileSync(cssPath, 'utf8');

assert(css.includes('--canvas: #fffaf2'), 'Must use the warm cream canvas token');
assert(css.includes('--ink: #292321'), 'Must use the warm charcoal ink token');
assert(css.includes('--amber: #ffb342'), 'Must use the brand amber token');
assert(css.includes('--page-width: 1080px'), 'Must use the 1080px page width');
assert(css.includes('--radius-card: 28px'), 'Must use 28px card corners');
assert(css.includes('.hero-title') && css.includes('.title-pill'), 'Must style the hero headline and inline pill');
assert(css.includes('.store-badge-dark') && css.includes('.store-badge-outline'), 'Must style the download badges');
assert(css.includes('.feature-grid') && css.includes('.principle-grid'), 'Must style feature and principle grids');
assert(css.includes('.marquee-track') && css.includes('@keyframes marquee-scroll'), 'Must style the screenshot marquee');
assert(css.includes('.faq-card'), 'Must style FAQ cards');
assert(css.includes('.download-card') && css.includes('.release-panel'), 'Must style the release download card');
assert(css.includes('.community-card') && css.includes('.pay-chip'), 'Must style the community card');
assert(css.includes('.site-footer') && css.includes('.footer-grid'), 'Must style the dark footer');
assert(css.includes('.has-reveal .reveal') && css.includes('.reveal.is-visible'), 'Must implement scroll reveal states');
assert(css.includes('prefers-reduced-motion: reduce'), 'Must respect reduced motion');
assert(css.includes('@media (max-width: 960px)') && css.includes('.site-header.is-open .site-nav'), 'Must implement the mobile navigation panel');
assert(css.includes('--tabby-amber') && css.includes('--tabby-charcoal'), 'Must retain legal page compatibility tokens');
assert(css.includes('.btn-primary') && css.includes('.navbar-inner') && css.includes('.footer-link'), 'Must style shared legal page header, buttons, and footer');
const privacyHtml = fs.readFileSync(path.join(docsDir, 'privacy.html'), 'utf8');
assert(privacyHtml.includes('.legal-hero') && privacyHtml.includes('.legal-body'), 'Privacy page must retain its inline legal layout styles');

console.log('✓ docs/styles.css tokens, layout, marquee, reveal, and legal compatibility verified');

// 3. Verify docs/app.js release engine and interaction setup
const jsPath = path.join(docsDir, 'app.js');
assert(fs.existsSync(jsPath), 'docs/app.js must exist');
const js = fs.readFileSync(jsPath, 'utf8');

assert(js.includes('api.github.com/repos/') && js.includes('Zalweb') && js.includes('Tabby'), 'Must fetch releases from the GitHub API');
assert(js.includes('apk-download-btn') && js.includes('ipa-download-btn'), 'Must update both download button groups');
assert(js.includes('releases/latest/download/Tabby.apk'), 'Must keep the canonical APK fallback');
assert(js.includes('releases/latest/download/Tabby.ipa'), 'Must keep the canonical IPA fallback');
assert(js.includes('applyReleaseData'), 'Must apply fetched release data');
assert(js.includes('ipa-size'), 'Must update IPA size labels');
assert(js.includes('escapeHtml') && js.includes('simpleMarkdown'), 'Must escape release notes before rendering');
assert(js.includes('setupMobileNav'), 'Must initialize the mobile navigation toggle');
assert(js.includes('setupRevealAnimations'), 'Must initialize scroll reveal');
assert(js.includes('setupHeaderState'), 'Must initialize the sticky header state');
assert(!js.includes('setupMockupInteractivity'), 'Must not keep the retired mockup interaction');
assert(!js.includes('setupFaqAccordion'), 'Must not keep the retired FAQ accordion script');

console.log('✓ docs/app.js release engine, mobile navigation, and reveal setup verified');

// 4. Verify mirrored landing/ directory and shared assets
const landingHtml = fs.readFileSync(path.join(landingDir, 'index.html'), 'utf8');
const landingCss = fs.readFileSync(path.join(landingDir, 'styles.css'), 'utf8');
const landingJs = fs.readFileSync(path.join(landingDir, 'app.js'), 'utf8');

assert.strictEqual(html, landingHtml, 'landing/index.html must strictly mirror docs/index.html');
assert.strictEqual(css, landingCss, 'landing/styles.css must strictly mirror docs/styles.css');
assert.strictEqual(js, landingJs, 'landing/app.js must strictly mirror docs/app.js');

for (const legal of ['privacy.html', 'terms.html']) {
  assert.strictEqual(
    fs.readFileSync(path.join(landingDir, legal), 'utf8'),
    fs.readFileSync(path.join(docsDir, legal), 'utf8'),
    `landing/${legal} must strictly mirror docs/${legal}`,
  );
}

const sharedAssets = [
  'assets/tabby-launcher.png',
  'assets/mascot-welcome.png',
  'assets/mascot-notebook.png',
  'assets/mascot-thinking.png',
  'assets/mascot-waiting.png',
  'assets/mascot-helpful.png',
  'assets/mascot-reminder.png',
  'assets/mascot-celebrating.png',
  'assets/screens/home-light.png',
  'assets/screens/home-dark.png',
  'assets/screens/login-light.png',
  'assets/screens/login-dark.png',
  'assets/screens/detail-light.png',
  'assets/screens/detail-dark.png',
];
for (const asset of sharedAssets) {
  const landingAsset = path.join(landingDir, asset);
  const docsAsset = path.join(docsDir, asset);
  assert(fs.existsSync(landingAsset), `landing/${asset} must exist`);
  assert(fs.existsSync(docsAsset), `docs/${asset} must exist`);
  assert(fs.readFileSync(landingAsset).equals(fs.readFileSync(docsAsset)), `docs/${asset} must mirror landing/${asset}`);
}

console.log('✓ landing/ and docs/ mirror pages and shared assets');

// 5. Simulate release update logic
function simulateUpdate(release) {
  let apkAsset = null;
  let ipaAsset = null;
  if (Array.isArray(release.assets)) {
    apkAsset = release.assets.find(a => a.name && a.name.endsWith('.apk') && a.name.includes('-')) ||
               release.assets.find(a => a.name && a.name.endsWith('.apk'));
    ipaAsset = release.assets.find(a => a.name && a.name.endsWith('.ipa'));
  }
  const apkUrl = apkAsset ? apkAsset.browser_download_url : 'https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.apk';
  const ipaUrl = ipaAsset ? ipaAsset.browser_download_url : 'https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.ipa';
  return {
    tagName: release.tag_name,
    apkUrl,
    ipaUrl,
    sizeMb: apkAsset ? (apkAsset.size / (1024 * 1024)).toFixed(1) + ' MB' : '70.2 MB',
    ipaSizeMb: ipaAsset ? (ipaAsset.size / (1024 * 1024)).toFixed(1) + ' MB' : '30.2 MB',
    filename: apkAsset ? apkAsset.name : 'Tabby.apk'
  };
}

const current = simulateUpdate({
  tag_name: 'v1.0.4+24',
  assets: [
    { name: 'Tabby-v1.0.4.apk', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4/Tabby-v1.0.4.apk', size: 73609244 },
    { name: 'Tabby.ipa', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4/Tabby.ipa', size: 31633412 }
  ]
});
assert.strictEqual(current.tagName, 'v1.0.4+24');
assert.strictEqual(current.apkUrl, 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4/Tabby-v1.0.4.apk');
assert.strictEqual(current.ipaUrl, 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4/Tabby.ipa');
assert.strictEqual(current.filename, 'Tabby-v1.0.4.apk');
assert.strictEqual(current.sizeMb, '70.2 MB');
assert.strictEqual(current.ipaSizeMb, '30.2 MB');

const next = simulateUpdate({
  tag_name: 'v1.0.5+25',
  assets: [
    { name: 'Tabby-v1.0.5.apk', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.5/Tabby-v1.0.5.apk', size: 75000000 }
  ]
});
assert.strictEqual(next.tagName, 'v1.0.5+25');
assert.strictEqual(next.filename, 'Tabby-v1.0.5.apk');
assert.strictEqual(next.sizeMb, '71.5 MB');
assert.strictEqual(next.ipaSizeMb, '30.2 MB');

console.log('✓ Release sync simulation verified');

// 6. Verify live Vercel deployment (page shell assertions only)
const https = require('https');
https.get('https://tabby-web-fawn.vercel.app', (res) => {
  assert.strictEqual(res.statusCode, 200, 'Live Vercel URL must return 200 OK');
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    assert(data.includes('Tabby — Keep tabs. Settle up.'), 'Live site must contain the Tabby title');
    assert(data.includes('Download APK') || data.includes('Download Tabby APK'), 'Live site must contain a download CTA');
    console.log('✓ Live Vercel deployment reachable with the Tabby title and download CTA.');
    console.log('ALL WEB TESTS PASSED SUCCESSFULLY (100%)');
  });
}).on('error', (err) => {
  console.error('Live URL error:', err);
  process.exitCode = 1;
});
