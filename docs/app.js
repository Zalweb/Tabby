/**
 * Tabby — automated release sync, mobile navigation, and scroll reveal.
 * Fetches optional metadata for the latest published release from
 * Zalweb/Tabby and keeps the page's light interactions accessible. Download
 * buttons always use the stable URLs declared in the HTML.
 */

(function () {
  'use strict';

  const GITHUB_OWNER = 'Zalweb';
  const GITHUB_REPO = 'Tabby';
  const RELEASES_API_URL = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;
  const versionTags = document.querySelectorAll('[data-role="version-tag"]');
  const apkSizes = document.querySelectorAll('[data-role="apk-size"]');
  const ipaSizes = document.querySelectorAll('[data-role="ipa-size"]');
  const liveStatusTexts = document.querySelectorAll('[data-role="live-status"]');

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return null;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function applyReleaseData(release) {
    const assets = release && Array.isArray(release.assets) ? release.assets : [];
    const apkAsset = assets.find((asset) => asset && asset.name === 'Tabby.apk');
    const ipaAsset = assets.find((asset) => asset && asset.name === 'Tabby.ipa');

    // Only a complete stable-name pair describes the release that the
    // canonical download buttons serve.
    if (!apkAsset || !ipaAsset) return false;

    const tagName = typeof release.tag_name === 'string' && release.tag_name.trim()
      ? release.tag_name.trim()
      : null;
    const apkSizeText = formatBytes(apkAsset.size);
    const ipaSizeText = formatBytes(ipaAsset.size);

    if (tagName) {
      versionTags.forEach((element) => {
        element.textContent = tagName;
      });
      liveStatusTexts.forEach((element) => {
        element.textContent = `Latest build: ${tagName} (Live)`;
      });
    } else {
      liveStatusTexts.forEach((element) => {
        element.textContent = 'Latest release downloads';
      });
    }

    if (apkSizeText) {
      apkSizes.forEach((element) => {
        element.textContent = apkSizeText;
      });
    }

    if (ipaSizeText) {
      ipaSizes.forEach((element) => {
        element.textContent = ipaSizeText;
      });
    }

    return true;
  }

  function showLatestDownloads() {
    versionTags.forEach((element) => {
      element.textContent = 'Latest';
    });
    apkSizes.forEach((element) => {
      element.textContent = 'Android app';
    });
    ipaSizes.forEach((element) => {
      element.textContent = 'iOS sideload';
    });
    liveStatusTexts.forEach((element) => {
      element.textContent = 'Latest release downloads';
    });
  }

  async function fetchLatestRelease() {
    liveStatusTexts.forEach((element) => {
      element.textContent = 'Checking for latest build…';
    });

    try {
      const response = await fetch(`${RELEASES_API_URL}?t=${Date.now()}`, {
        headers: { Accept: 'application/vnd.github.v3+json' },
        cache: 'no-store',
      });
      if (!response.ok) {
        throw new Error(`Release API returned status ${response.status}`);
      }
      const release = await response.json();
      if (!applyReleaseData(release)) {
        showLatestDownloads();
      }
    } catch (error) {
      console.warn('[Tabby] Release metadata unavailable; stable download URLs remain active.', error);
      showLatestDownloads();
    }
  }

  function setupMobileNav() {
    const header = document.querySelector('[data-header]');
    const toggle = document.querySelector('[data-nav-toggle]');
    const nav = document.getElementById('siteNav');
    if (!header || !toggle || !nav) return;

    const setOpen = (open) => {
      header.classList.toggle('is-open', open);
      toggle.setAttribute('aria-expanded', String(open));
      toggle.setAttribute('aria-label', open ? 'Close navigation menu' : 'Open navigation menu');
    };

    toggle.addEventListener('click', () => {
      setOpen(!header.classList.contains('is-open'));
    });

    nav.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => setOpen(false));
    });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && header.classList.contains('is-open')) {
        setOpen(false);
        toggle.focus();
      }
    });

    document.addEventListener('click', (event) => {
      if (header.classList.contains('is-open') && !header.contains(event.target)) {
        setOpen(false);
      }
    });
  }

  function setupHeaderState() {
    const header = document.querySelector('[data-header]');
    if (!header) return;
    const update = () => header.classList.toggle('is-scrolled', window.scrollY > 6);
    update();
    window.addEventListener('scroll', update, { passive: true });
  }

  function setupRevealAnimations() {
    const elements = document.querySelectorAll('.reveal');
    if (!elements.length || !('IntersectionObserver' in window)) return;

    document.documentElement.classList.add('has-reveal');
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.08,
      rootMargin: '0px 0px -8% 0px',
    });

    elements.forEach((element) => observer.observe(element));
    requestAnimationFrame(() => {
      elements.forEach((element) => {
        const rect = element.getBoundingClientRect();
        if (rect.top < window.innerHeight && rect.bottom > 0) {
          element.classList.add('is-visible');
        }
      });
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    fetchLatestRelease();
    setupMobileNav();
    setupHeaderState();
    setupRevealAnimations();
  });
})();
