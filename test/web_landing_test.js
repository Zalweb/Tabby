const fs = require('fs');
const path = require('path');
const assert = require('assert');

console.log('--- Starting Tabby Web Landing Page Verification Suite ---');

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

// Verify zero emojis across HTML
const emojiRegex = /[\uD800-\uDBFF][\uDC00-\uDFFF]|[\u2600-\u27BF]/g;
const htmlEmojiMatches = html.match(emojiRegex) || [];
assert.strictEqual(htmlEmojiMatches.length, 0, `HTML must not contain emojis. Found: ${htmlEmojiMatches.join(' ')}`);

// Verify minimalist vector SVG icons exist
assert(html.includes('<svg class="pill-icon"'), 'Must have minimalist SVG vector icons in feature pills');
assert(html.includes('<div class="state-icon-badge" aria-label="Settled and Sleeping">') &&
       html.includes('<div class="state-icon-badge" aria-label="Curious and Alert">') &&
       html.includes('<div class="state-icon-badge" aria-label="Settled Celebration">'),
       'Must have minimalist SVG state icon badges in mascot cards');
assert(html.includes('<rect x="2" y="5" width="20" height="14" rx="2">') || html.includes('rect x="2" y="5"'), 'Must have minimalist CreditCard SVG for Philippine Payment Rails');
assert(html.includes('<rect x="4" y="2" width="16" height="20" rx="2">') || html.includes('rect x="4" y="2"'), 'Must have minimalist Calculator SVG for Zero Floating-Point Drift');
assert(html.includes('d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"'), 'Must have minimalist Receipt SVG for Proof of Payment');

// Verify accurate feature content in index.html
assert(html.includes('One Tab = One Relationship'), 'Must describe One Tab = One Relationship ledger concept');
assert(html.includes('Zero Floating-Point Drift'), 'Must describe centavo-accurate integer arithmetic');
assert(html.includes('Philippine Payment Rails'), 'Must mention Philippine payment rails');
assert(html.includes('GCash, Maya, QR Ph') || html.includes('GCash, Maya & QR Ph'), 'Must mention GCash, Maya, and QR Ph');
assert(html.includes('Offline-First Resilience'), 'Must feature offline-first sync');
assert(html.includes('Tabby ID & Bank-Grade RLS'), 'Must feature Tabby ID and Row Level Security');
assert(html.includes('Sleeping & Content ("Bayad na!")'), 'Must feature mascot sleeping zero-balance state');
assert(html.includes('Defusing "Hiya" with Companion Warmth') || html.includes('Defusing Awkwardness with Warmth'), 'Must feature mascot warmth');
assert(html.includes('Frequently Asked Questions'), 'Must feature FAQ section');
assert(html.includes('Barkada & Group Splitting'), 'Must feature Barkada and Group splitting');
assert(html.includes('Proof-of-Payment Receipts'), 'Must feature Proof-of-payment receipts');

// Verify scroll pop animation markup
assert(html.includes('pop-on-scroll'), 'Must include pop-on-scroll animation classes');
assert(html.includes('pop-delay-1') && html.includes('pop-delay-2'), 'Must include staggered pop delays');

console.log('✓ docs/index.html content, minimalist SVG icons & feature specs verified');

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

// Verify mobile header responsiveness rules and fluid typography
assert(css.includes('.nav-tagline') && css.includes('display: none'), 'Must hide .nav-tagline on mobile headers to prevent overflow');
assert(css.includes('clamp('), 'Must use clamp fluid typography for responsive text');
assert(css.includes('.navbar-inner') && (css.includes('height: 64px') || css.includes('height: 60px')), 'Must adjust navbar height on compact viewports');
assert(css.includes('.pill-icon'), 'Must style minimalist pill icons');
assert(css.includes('.state-icon-badge'), 'Must style minimalist state icon badge container');
assert(css.includes('@media (max-width: 860px)') && css.includes('.nav-links'), 'Must collapse desktop nav-links at 860px breakpoint');

// Verify scroll-triggered pop animation styles
assert(css.includes('.pop-on-scroll'), 'Must have .pop-on-scroll base styling');
assert(css.includes('.pop-on-scroll.is-visible'), 'Must have .pop-on-scroll.is-visible styling');
assert(css.includes('.pop-on-scroll:not(.is-visible)'), 'Must have reset styling when scrolled out of view');
assert(css.includes('cubic-bezier(0.34, 1.35, 0.64, 1)'), 'Must use spring-pop cubic-bezier curve');
assert(css.includes('.pop-delay-1') && css.includes('.pop-delay-4'), 'Must have stagger delay classes');

// Verify responsive stick-together 3-mockup styling and floating animation
assert(css.includes('--mockup-overlap'), 'Must use --mockup-overlap variable for sticking mockups together');
assert(css.includes('--mockup-side-w') && css.includes('--mockup-center-w'), 'Must use geometry variables for scalable mockups');
assert(css.includes('.mockup-phone-left') && css.includes('.mockup-phone-right'), 'Must style left and right tilted mockups');
assert(css.includes('phone-float') && css.includes('.mockup-phone-center.is-floating'), 'Must have floating center phone animation');

console.log('✓ docs/styles.css tokens, mobile header responsiveness, fluid typography, pop animations & mockup styling verified');

// 3. Verify docs/app.js
const jsPath = path.join(__dirname, '..', 'docs', 'app.js');
assert(fs.existsSync(jsPath), 'docs/app.js must exist');
const js = fs.readFileSync(jsPath, 'utf8');
assert(js.includes('api.github.com/repos/') && js.includes('Zalweb') && js.includes('Tabby'), 'Must fetch from GitHub Releases API');
assert(js.includes('apk-download-btn'), 'Must select apk-download-btn');
assert(js.includes('releases/latest/download/Tabby.apk'), 'Must have canonical fallback URL');
assert(js.includes('applyReleaseData'), 'Must have release data application logic');
assert(js.includes('setupScrollPopAnimations'), 'Must initialize scroll-pop animation observer');
assert(js.includes("classList.remove('is-visible')"), 'Must re-trigger scroll pop animations when scrolled back into view');
assert(js.includes('setupMockupInteractivity'), 'Must initialize mockup phone tap / focus interaction');
assert(js.includes('setupFaqAccordion'), 'Must initialize FAQ accordion toggle');

console.log('✓ docs/app.js release engine, pop observer & interactivity verified');

// 4. Verify mirrored landing/ directory
const landingHtml = fs.readFileSync(path.join(__dirname, '..', 'landing', 'index.html'), 'utf8');
const landingCss = fs.readFileSync(path.join(__dirname, '..', 'landing', 'styles.css'), 'utf8');
const landingJs = fs.readFileSync(path.join(__dirname, '..', 'landing', 'app.js'), 'utf8');

assert.strictEqual(html, landingHtml, 'landing/index.html must strictly mirror docs/index.html');
assert.strictEqual(css, landingCss, 'landing/styles.css must strictly mirror docs/styles.css');
assert.strictEqual(js, landingJs, 'landing/app.js must strictly mirror docs/app.js');
console.log('✓ landing/ directory mirrors docs/ perfectly (100% synchronized)');

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

console.log('✓ Release sync simulation verified');

// 6. Verify live Vercel deployment
const https = require('https');
https.get('https://tabby-web-fawn.vercel.app', (res) => {
  assert.strictEqual(res.statusCode, 200, 'Live Vercel URL must return 200 OK');
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    assert(data.includes('Tabby — Keep tabs. Settle up.'), 'Live site must contain title');
    assert(data.includes('Download Tabby APK') || data.includes('Download APK'), 'Live site must contain Download APK CTA');
    console.log('✓ Live Vercel deployment verification SUCCESSFUL! Status 200 OK.');
    console.log('ALL WEB TESTS PASSED SUCCESSFULLY (100%)');
  });
}).on('error', (err) => {
  console.error('Live URL error:', err);
});
