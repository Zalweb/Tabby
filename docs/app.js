(() => {
  'use strict';

  const releaseUrl = 'https://api.github.com/repos/Zalweb/Tabby/releases/latest';
  const downloads = {
    android: document.querySelectorAll('[data-platform-download="android"]'),
    ios: document.querySelectorAll('[data-platform-download="ios"]'),
  };
  const priorRelease = {
    android: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4+24/Tabby-v1.0.4+24.apk',
    ios: 'https://github.com/Zalweb/Tabby/releases/download/v1.0.4+24/Tabby-v1.0.4+24.ipa',
  };

  function trustedAsset(release, extension) {
    if (!release || typeof release.tag_name !== 'string' || !Array.isArray(release.assets)) return null;

    const stableName = extension === 'apk' ? 'Tabby.apk' : 'Tabby.ipa';
    const versionedName = `Tabby-${release.tag_name}.${extension}`;
    const asset = release.assets.find((item) => item.name === stableName) ||
      release.assets.find((item) => item.name === versionedName);
    if (!asset || typeof asset.browser_download_url !== 'string') return null;

    try {
      const url = new URL(asset.browser_download_url);
      const parts = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
      const expectedName = asset.name;
      if (url.origin !== 'https://github.com' ||
          parts.length !== 6 ||
          parts[0] !== 'Zalweb' ||
          parts[1] !== 'Tabby' ||
          parts[2] !== 'releases' ||
          parts[3] !== 'download' ||
          parts[4] !== release.tag_name ||
          parts[5] !== expectedName ||
          ![stableName, versionedName].includes(expectedName)) {
        return null;
      }
      return url.href;
    } catch (_) {
      return null;
    }
  }

  function updatePlatform(platform, extension, release) {
    if (!/^v\d+\.\d+\.\d+\+[1-9]\d*$/.test(release.tag_name) || !Array.isArray(release.assets)) return;
    const url = trustedAsset(release, extension);
    if (url) {
      downloads[platform].forEach((link) => link.setAttribute('href', url));
      return;
    }

    const names = extension === 'apk' ? ['Tabby.apk', `Tabby-${release.tag_name}.apk`] : ['Tabby.ipa', `Tabby-${release.tag_name}.ipa`];
    const releaseHasPlatformAsset = release.assets.some((asset) => names.includes(asset.name));
    if (!releaseHasPlatformAsset) {
      downloads[platform].forEach((link) => link.setAttribute('href', priorRelease[platform]));
    }
  }

  if (typeof IntersectionObserver === 'function') {
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      }
    }, { threshold: 0.25 });
    document.querySelectorAll('.benefit-card').forEach((card) => observer.observe(card));
  }

  if (typeof fetch === 'function') {
    fetch(releaseUrl, { headers: { Accept: 'application/vnd.github+json' } })
      .then((response) => {
        if (!response.ok) throw new Error('Release lookup unavailable');
        return response.json();
      })
      .then((release) => {
        if (!release || typeof release !== 'object') return;
        updatePlatform('android', 'apk', release);
        updatePlatform('ios', 'ipa', release);
      })
      .catch(() => {
        // Keep the stable release aliases in the HTML active.
      });
  }
})();
