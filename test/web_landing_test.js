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
assert(!html.includes('id="how-it-works"') && html.includes('id="download"') && html.includes('id="faq"'), 'Must omit how-it-works and keep download and FAQ sections');

assert(html.includes('data-role="apk-download-btn"'), 'Must have APK download buttons');
assert(html.includes('data-role="ipa-download-btn"'), 'Must have IPA download buttons');
assert(html.includes('data-role="version-tag"'), 'Must have version tag elements');
assert(html.includes('data-role="apk-size"'), 'Must have APK size elements');
assert(html.includes('data-role="ipa-size"'), 'Must have IPA size elements');
assert(html.includes('data-role="live-status"'), 'Must have live release status elements');
assert(html.includes('data-role="version-tag">Latest</span>'), 'No-script version label must stay neutral');
assert(html.includes('data-role="apk-size">Android app</span>'), 'No-script APK label must use generic platform information');
assert(html.includes('data-role="ipa-size">iOS sideload</span>'), 'No-script IPA label must use generic platform information');
assert(!html.includes('v1.0.4+24') && !html.includes('70.2 MB') && !html.includes('30.2 MB'), 'HTML must not hardcode old release metadata');
const downloadButtons = [...html.matchAll(/<a\b[^>]*\bdata-role="(apk|ipa)-download-btn"[^>]*>/g)];
assert(downloadButtons.length >= 2, 'Must have platform download buttons');
for (const button of downloadButtons) {
  const platform = button[1];
  const openingTag = button[0];
  const asset = platform === 'apk' ? 'Tabby.apk' : 'Tabby.ipa';
  const canonicalUrl = `https://github.com/Zalweb/Tabby/releases/latest/download/${asset}`;
  assert(openingTag.includes(`href="${canonicalUrl}"`), `Every ${platform.toUpperCase()} button must use its stable latest URL`);
  if (platform === 'apk') {
    assert(openingTag.includes('download="Tabby.apk"'), 'Every APK button must keep the stable filename');
  }
}
assert(html.includes('data-nav-toggle'), 'Must have a mobile navigation toggle');
assert(html.includes('app.js') && html.includes('styles.css'), 'Must load app.js and styles.css');

const hero = html.slice(html.indexOf('<!-- Hero -->'), html.indexOf('<!-- Features -->'));
assert(hero.includes('assets/screens/home-light.png'), 'Hero must keep the current Home screenshot');
assert(!hero.includes('hero-mascot') && !hero.includes('waving hello'), 'Hero must not include the decorative waving cat');
assert(!hero.includes('hero-chip-bottom') && !hero.includes('Exact to the centavo'), 'Hero must not include the centavo decoration');

const downloadSection = html.slice(html.indexOf('id="download"'), html.indexOf('<!-- Community -->'));
assert(downloadSection.includes('<h2>Download Tabby</h2>'), 'Download card must have a clear Download Tabby heading');
assert(downloadSection.includes('Download for Android') && downloadSection.includes('Download for iOS'), 'Download card must keep both platform actions');
assert(downloadSection.includes('APK · Android 8.0+') && downloadSection.includes('IPA · iOS 15+'), 'Download card must state formats and minimum requirements');
assert(downloadSection.includes('unsigned') && downloadSection.includes('AltStore or Sideloadly'), 'Download card must explain iOS sideloading');
assert(!downloadSection.includes('Release details') && !downloadSection.includes('What\'s new'), 'Download card must omit the redundant release and changelog panels');
assert(!html.includes('data-role="changelog-body"'), 'Landing HTML must not expose a release-note insertion target');

assert(html.includes('assets/tabby-launcher.png'), 'Must use the current launcher icon');
assert(html.includes('class="feature-mascot feature-mascot-notebook"'), 'Must keep the notebook mascot in the feature cards');
assert(html.includes('assets/mascot-thinking.png') && html.includes('assets/mascot-celebrating.png') && html.includes('assets/mascot-reminder.png'), 'Must use situation mascot artwork');
assert(html.includes('assets/screens/home-light.png') && html.includes('assets/screens/home-dark.png'), 'Must show current light and dark home screenshots');
assert(html.includes('assets/screens/login-light.png') && html.includes('assets/screens/detail-light.png'), 'Must show welcome and tab detail screenshots');
assert(!html.includes('preview-home.png') && !html.includes('preview-banner.png'), 'Must not reference outdated app screenshots');
assert(!html.includes('tabby-icon.jpg'), 'Must not reference the legacy icon asset');

assert(html.includes('One tab per friendship'), 'Feature cards must describe one tab per friendship');
assert(html.includes('Custom amounts'), 'Feature cards must describe custom split amounts');
assert(html.includes('Centavo-exact'), 'Feature cards must describe centavo-exact math');
assert(!html.includes('Recipient confirmed') && html.includes('recipient confirms'), 'Must describe recipient-confirmed payments outside the removed hero chip');
assert(html.includes('Append-only history'), 'Must describe append-only ledger history');
assert(html.includes('Offline-durable'), 'Must describe durable offline behavior');
assert(html.includes('Encrypted at rest'), 'Must describe encrypted payment fields');
assert(html.includes('Group tabs'), 'Must describe group tabs');
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
assert(!css.includes('.hero-mascot') && !css.includes('.hero-chip-bottom'), 'Must retire styles for removed hero decorations');
assert(css.includes('.store-badge-dark') && css.includes('.store-badge-outline'), 'Must style the download badges');
assert(css.includes('.feature-grid') && css.includes('.principle-grid'), 'Must style feature and principle grids');
assert(css.includes('.marquee-track') && css.includes('@keyframes marquee-scroll'), 'Must style the screenshot marquee');
assert(css.includes('.faq-card'), 'Must style FAQ cards');
assert(css.includes('.download-card') && !css.includes('.release-panel'), 'Must style the simplified download card without release details');
assert(css.includes('.feature-mascot-thinking') && css.includes('@keyframes feature-thinking-settle'), 'Thinking mascot must animate on feature-card entrance');
assert(css.includes('.feature-mascot-notebook') && css.includes('@keyframes feature-notebook-settle'), 'Notebook mascot must have its own entrance motion');
assert(css.includes('.feature-mascot-celebrating') && css.includes('@keyframes feature-celebration'), 'Celebrating mascot must have a finite entrance motion');
assert(css.includes('@media (prefers-reduced-motion: no-preference)'), 'Mascot motion must be disabled when reduced motion is preferred');
assert(!css.includes('.changelog') && !css.includes('.release-row'), 'Must retire unused release panel and changelog styles');
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
assert(js.includes('applyReleaseData'), 'Must apply fetched release data');
assert(js.includes('ipa-size'), 'Must update IPA size labels');
assert(js.includes("asset.name === 'Tabby.apk'") && js.includes("asset.name === 'Tabby.ipa'"), 'Metadata must come from the exact stable-named asset pair');
assert(!js.includes('localStorage'), 'Release metadata must not be read from or written to local storage');
assert(!/\.setAttribute\(\s*['"](?:href|download)['"]/.test(js), 'Release metadata must never change download URLs or filenames');
assert(!js.includes('v1.0.4+24') && !js.includes('70.2 MB') && !js.includes('30.2 MB'), 'Updater must not contain fixed old release metadata');
assert(html.includes('releases/latest/download/Tabby.apk') && html.includes('releases/latest/download/Tabby.ipa'), 'HTML must declare both canonical latest URLs');
assert(!js.includes('escapeHtml') && !js.includes('simpleMarkdown'), 'Release-note rendering must be removed');
assert(!js.includes('changelog') && !js.includes('innerHTML'), 'Release notes must never be inserted into the landing DOM');
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

// 5. Execute the real release updater against stable-name metadata and stale-cache failure fixtures.
async function runReleaseUpdater({ release, fetchError, cachedRelease }) {
  const vm = require('vm');
  const createElements = (count, attributes = {}, textContent = '') => Array.from({ length: count }, () => ({
    attributes: { ...attributes },
    textContent,
    setAttribute(name, value) { this.attributes[name] = String(value); },
    getAttribute(name) { return this.attributes[name] || null; },
  }));
  const apkHref = 'https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.apk';
  const ipaHref = 'https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.ipa';
  const elements = {
    '[data-role="apk-download-btn"]': createElements(3, { href: apkHref, download: 'Tabby.apk' }),
    '[data-role="ipa-download-btn"]': createElements(2, { href: ipaHref }),
    '[data-role="version-tag"]': createElements(2, {}, 'Latest'),
    '[data-role="apk-size"]': createElements(1, {}, 'Android app'),
    '[data-role="ipa-size"]': createElements(1, {}, 'iOS sideload'),
    '[data-role="live-status"]': createElements(2, {}, 'Latest release downloads'),
    '.reveal': [],
  };
  let storageReads = 0;
  let storageWrites = 0;
  let onReady;
  const document = {
    querySelectorAll(selector) { return elements[selector] || []; },
    querySelector() { return null; },
    getElementById() { return null; },
    addEventListener(type, handler) { if (type === 'DOMContentLoaded') onReady = handler; },
    documentElement: { classList: { add() {} } },
  };
  const context = {
    document,
    window: { scrollY: 0, addEventListener() {} },
    localStorage: {
      getItem() { storageReads += 1; return cachedRelease; },
      setItem() { storageWrites += 1; },
    },
    fetch: async () => {
      if (fetchError) throw fetchError;
      return { ok: true, json: async () => release };
    },
    console: { warn() {} },
    Date,
    Promise,
    requestAnimationFrame(callback) { callback(); },
  };
  vm.runInNewContext(js, context, { filename: 'docs/app.js' });
  assert.strictEqual(typeof onReady, 'function', 'Release updater must initialize on DOMContentLoaded');
  onReady();
  await new Promise(resolve => setImmediate(resolve));

  return { elements, storageReads, storageWrites, apkHref, ipaHref };
}

async function verifyReleaseRuntime() {
  const newRelease = {
    tag_name: 'v2.0.0+40',
    body: '<script>must not be inserted</script>',
    assets: [
      {
        name: 'Tabby-v2.0.0+40.apk',
        browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v2.0.0%2B40/Tabby-v2.0.0%2B40.apk',
        size: 1024,
      },
      {
        name: 'Tabby-v2.0.0+40.ipa',
        browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v2.0.0%2B40/Tabby-v2.0.0%2B40.ipa',
        size: 2048,
      },
      {
        name: 'Tabby.apk',
        browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v2.0.0%2B40/Tabby.apk',
        size: 80 * 1024 * 1024,
      },
      {
        name: 'Tabby.ipa',
        browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v2.0.0%2B40/Tabby.ipa',
        size: 40 * 1024 * 1024,
      },
    ],
  };
  const updated = await runReleaseUpdater({ release: newRelease });
  for (const button of updated.elements['[data-role="apk-download-btn"]']) {
    assert.strictEqual(button.getAttribute('href'), updated.apkHref, 'Every APK action must keep its canonical latest URL');
    assert.strictEqual(button.getAttribute('download'), 'Tabby.apk', 'APK actions must keep their canonical filename');
  }
  for (const button of updated.elements['[data-role="ipa-download-btn"]']) {
    assert.strictEqual(button.getAttribute('href'), updated.ipaHref, 'Every IPA action must keep its canonical latest URL');
  }
  assert(updated.elements['[data-role="version-tag"]'].every(element => element.textContent === 'v2.0.0+40'), 'Version labels must follow the fetched release');
  assert.strictEqual(updated.elements['[data-role="apk-size"]'][0].textContent, '80.0 MB', 'APK size must come from the exact Tabby.apk asset');
  assert.strictEqual(updated.elements['[data-role="ipa-size"]'][0].textContent, '40.0 MB', 'IPA size must come from the exact Tabby.ipa asset');
  assert(updated.elements['[data-role="live-status"]'].every(element => element.textContent === 'Latest build: v2.0.0+40 (Live)'));
  assert.strictEqual(updated.storageReads, 0, 'Updater must not read old cached metadata');
  assert.strictEqual(updated.storageWrites, 0, 'Updater must not cache release metadata');

  const staleCache = JSON.stringify({
    data: {
      tag_name: 'v0.9.0+1',
      assets: [
        { name: 'Tabby-v0.9.0+1.apk', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v0.9.0/Tabby-v0.9.0+1.apk', size: 1024 },
        { name: 'Tabby-v0.9.0+1.ipa', browser_download_url: 'https://github.com/Zalweb/Tabby/releases/download/v0.9.0/Tabby-v0.9.0+1.ipa', size: 2048 },
      ],
    },
    timestamp: Date.now(),
  });
  const failed = await runReleaseUpdater({ cachedRelease: staleCache, fetchError: new Error('simulated release API failure') });
  for (const button of failed.elements['[data-role="apk-download-btn"]']) {
    assert.strictEqual(button.getAttribute('href'), failed.apkHref, 'API failure must leave every APK latest URL stable');
    assert.strictEqual(button.getAttribute('download'), 'Tabby.apk', 'API failure must leave the APK filename stable');
  }
  for (const button of failed.elements['[data-role="ipa-download-btn"]']) {
    assert.strictEqual(button.getAttribute('href'), failed.ipaHref, 'API failure must leave every IPA latest URL stable');
  }
  assert(failed.elements['[data-role="version-tag"]'].every(element => element.textContent === 'Latest'), 'API failure must keep a neutral version label');
  assert.strictEqual(failed.elements['[data-role="apk-size"]'][0].textContent, 'Android app');
  assert.strictEqual(failed.elements['[data-role="ipa-size"]'][0].textContent, 'iOS sideload');
  assert(failed.elements['[data-role="live-status"]'].every(element => element.textContent === 'Latest release downloads'));
  assert.strictEqual(failed.storageReads, 0, 'Existing stale cache must not be read after API failure');
  assert.strictEqual(failed.storageWrites, 0, 'Existing stale cache must not be rewritten after API failure');
  console.log('✓ Latest stable APK/IPA metadata updates without changing links; stale-cache API failure stays neutral and does not insert release notes');
}

verifyReleaseRuntime().then(() => {
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
}).catch((error) => {
  console.error('Release runtime verification failed:', error);
  process.exitCode = 1;
});
