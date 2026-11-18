'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const https = require('node:https');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const landing = path.join(root, 'landing');
const docs = path.join(root, 'docs');
const read = (directory, file) => fs.readFileSync(path.join(directory, file), 'utf8');
const staticApk = 'https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.apk';
const staticIpa = 'https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.ipa';
const pinnedApk = 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4+24/Tabby-v1.0.4+24.apk';
const pinnedIpa = 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4+24/Tabby-v1.0.4+24.ipa';

async function runReleaseScript(release, online = true) {
  const makeLink = href => ({
    href,
    setAttribute(name, value) {
      if (name === 'href') this.href = value;
    },
  });
  const links = { android: [makeLink(staticApk)], ios: [makeLink(staticIpa)] };
  const sandbox = {
    URL,
    document: {
      querySelectorAll(selector) {
        return selector.includes('android') ? links.android : links.ios;
      },
    },
    fetch: online === null ? undefined : online
      ? async (url, options) => {
        assert.equal(url, 'https://api.github.com/repos/Zalweb/Tabby/releases/latest');
        assert.equal(options.headers.Accept, 'application/vnd.github+json');
        return { ok: true, json: async () => release };
      }
      : async () => { throw new Error('offline fixture'); },
  };
  vm.runInNewContext(read(landing, 'app.js'), sandbox);
  await new Promise((resolve) => setImmediate(resolve));
  return links;
}

async function verify() {
  const html = read(landing, 'index.html');
  assert(html.includes('<title>Tabby — Keep tabs. Settle up.</title>'));
  assert(html.includes('<h1 id="hero-title">Keep tabs.<br><span>Settle up.</span></h1>'));
  assert(html.includes('Track shared expenses, split to the centavo, and settle with the recipient’s confirmation.'));
  assert(html.includes('Pay through your own wallet. Tabby tracks the balance.'));
  assert(!html.includes('class="eyebrow"') && !html.includes('benefit-number'));
  assert(!/aria-hidden="true">0[123]<\/span>/.test(html));
  assert(!html.includes('<p>Keep tabs. Settle up.</p>'));
  assert(html.includes('href="https://sideloadly.io/"') && html.includes('iOS 15+'));
  for (const id of ['features', 'screens', 'download']) assert(html.includes(`id="${id}"`));
  const visuals = [
    'assets/tabby-launcher.png',
    'assets/mascot-thinking.png',
    'assets/mascot-notebook.png',
    'assets/mascot-celebrating.png',
    'assets/screens/home-light.png',
    'assets/screens/detail-light.png',
    'assets/screens/login-light.png',
  ];
  for (const asset of visuals) {
    assert(html.includes(asset), `Landing uses current Tabby visual ${asset}`);
    assert(fs.existsSync(path.join(landing, asset)), `${asset} exists`);
  }
  for (const platform of ['android', 'ios']) {
    const link = html.match(new RegExp(`<a[^>]+data-platform-download="${platform}"[^>]+href="([^"]+)"`));
    assert(link, `${platform} download link exists`);
    assert.equal(link[1], platform === 'android' ? staticApk : staticIpa, `${platform} has the stable no-JS download alias`);
  }
  assert(html.includes('Mac or Windows') && html.includes('Sideloadly') && html.includes('Apple ID'));
  assert(html.includes('href="/privacy"') && html.includes('href="/terms"'));
  assert(!/FAQ|Community|reviews|testimonials|users downloaded|Powered by Flutter|Supabase|70\.2 MB|30\.2 MB/.test(html));
  assert(!/class="(?:faq|stat|community|release-panel)/i.test(html));
  assert(!/[\uD800-\uDBFF][\uDC00-\uDFFF]|[\u2600-\u27BF]/.test(html), 'Landing contains no emoji copy');
  console.log('✓ Minimal page copy, Tabby visuals, no-JS links, and legal/install details verified');

  const css = read(landing, 'styles.css');
  for (const token of ['--canvas: #fffaf2', '--ink: #292321', '--amber: #ffb342']) assert(css.includes(token));
  assert(css.includes('.hero-art') && css.includes('.benefit-grid') && css.includes('.screen-grid'));
  assert(css.includes('@media (max-width: 640px)') && css.includes('@media (max-width: 360px)'));
  assert(css.includes(':focus-visible') && css.includes('prefers-reduced-motion: reduce'));
  assert(css.includes('.navbar-inner') && css.includes('.btn-primary') && css.includes('--tabby-amber'));
  assert(!css.includes('.site-header.is-open') && !css.includes('.marquee-track'));
  console.log('✓ Responsive, keyboard-focus, reduced-motion, and legal-page styles verified');

  const files = ['index.html', 'styles.css', 'app.js', 'privacy.html', 'terms.html'];
  for (const file of files) assert.equal(read(landing, file), read(docs, file), `landing/${file} mirrors docs/${file}`);
  for (const asset of visuals) {
    assert(fs.readFileSync(path.join(landing, asset)).equals(fs.readFileSync(path.join(docs, asset))), `${asset} mirrors`);
  }
  for (const legal of ['privacy.html', 'terms.html']) {
    const legalHtml = read(docs, legal);
    assert(legalHtml.includes('.legal-hero') && legalHtml.includes('.legal-body'));
    assert(!legalHtml.includes('/#faq') && !legalHtml.includes('/#why-tabby'));
    assert(legalHtml.includes('href="/#download"'));
  }
  console.log('✓ Landing/docs pages and legal surfaces mirror byte-for-byte');

  const latestTag = 'v1.0.5+25';
  const releaseBase = `https://github.com/Zalweb/Tabby/releases/download/${encodeURIComponent(latestTag)}`;
  const latest = await runReleaseScript({
    tag_name: latestTag,
    assets: [
      { name: 'Tabby.apk', browser_download_url: `${releaseBase}/Tabby.apk` },
      { name: 'Tabby.ipa', browser_download_url: `${releaseBase}/Tabby.ipa` },
    ],
  });
  assert.equal(latest.android[0].href, `${releaseBase}/Tabby.apk`);
  assert.equal(latest.ios[0].href, `${releaseBase}/Tabby.ipa`);

  const partial = await runReleaseScript({
    tag_name: latestTag,
    assets: [{ name: `Tabby-${latestTag}.apk`, browser_download_url: `${releaseBase}/Tabby-${latestTag}.apk` }],
  });
  assert.equal(partial.android[0].href, `${releaseBase}/Tabby-${latestTag}.apk`);
  assert.equal(partial.ios[0].href, pinnedIpa, 'Missing platform keeps its working pinned fallback');

  const untrusted = await runReleaseScript({
    tag_name: latestTag,
    assets: [{ name: 'Tabby.apk', browser_download_url: `https://evil.example/${latestTag}/Tabby.apk` }],
  });
  assert.equal(untrusted.android[0].href, staticApk, 'Untrusted origins never replace a download link');
  assert.equal(untrusted.ios[0].href, pinnedIpa, 'A confirmed missing iOS asset uses the last known working IPA');
  const offline = await runReleaseScript(null, false);
  assert.equal(offline.android[0].href, staticApk);
  assert.equal(offline.ios[0].href, staticIpa);
  const noJavaScript = await runReleaseScript(null, null);
  assert.equal(noJavaScript.android[0].href, staticApk);
  assert.equal(noJavaScript.ios[0].href, staticIpa);
  console.log('✓ Latest stable/versioned assets, missing assets, untrusted origins, offline, and no-JS aliases verified');

  if (process.env.WEB_LANDING_LIVE === '1') {
    const response = await new Promise((resolve, reject) => {
      https.get('https://tabby-web-fawn.vercel.app', (res) => {
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => { body += chunk; });
        res.on('end', () => resolve({ status: res.statusCode, body }));
      }).on('error', reject);
    });
    assert.equal(response.status, 200, 'Live Vercel shell returns HTTP 200');
    assert(response.body.includes('Keep tabs.') && response.body.includes('Get Tabby'), 'Live Vercel shell has the updated title and CTA');
    console.log('✓ Live Vercel landing shell returned HTTP 200');
  } else {
    console.log('• Live Vercel shell check skipped (set WEB_LANDING_LIVE=1 to opt in)');
  }
}

verify().then(() => {
  console.log('ALL WEB TESTS PASSED SUCCESSFULLY (100%)');
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
