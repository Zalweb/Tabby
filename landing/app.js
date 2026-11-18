/**
 * Tabby — automated release sync, mobile navigation, and scroll reveal.
 * Fetches the latest published release from Zalweb/Tabby, updates every
 * download surface, and keeps the page's light interactions accessible.
 */

(function () {
  'use strict';

  const GITHUB_OWNER = 'Zalweb';
  const GITHUB_REPO = 'Tabby';
  const RELEASES_API_URL = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;
  const CANONICAL_APK_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download/Tabby.apk`;
  const CANONICAL_IPA_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download/Tabby.ipa`;

  const DEFAULT_VERSION = 'v1.0.4+24';
  const DEFAULT_RELEASE_DATE = 'November 18, 2026';
  const DEFAULT_APK_SIZE = '70.2 MB';
  const DEFAULT_IPA_SIZE = '30.2 MB';

  const apkDownloadBtns = document.querySelectorAll('[data-role="apk-download-btn"]');
  const ipaDownloadBtns = document.querySelectorAll('[data-role="ipa-download-btn"]');
  const versionTags = document.querySelectorAll('[data-role="version-tag"]');
  const releaseDates = document.querySelectorAll('[data-role="release-date"]');
  const apkSizes = document.querySelectorAll('[data-role="apk-size"]');
  const ipaSizes = document.querySelectorAll('[data-role="ipa-size"]');
  const apkFilenames = document.querySelectorAll('[data-role="apk-filename"]');
  const liveStatusTexts = document.querySelectorAll('[data-role="live-status"]');
  const changelogBody = document.querySelector('[data-role="changelog-body"]');

  function formatBytes(bytes, fallback) {
    if (!bytes || isNaN(bytes)) return fallback;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function formatDate(isoString) {
    if (!isoString) return DEFAULT_RELEASE_DATE;
    try {
      return new Date(isoString).toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });
    } catch (error) {
      return DEFAULT_RELEASE_DATE;
    }
  }

  /**
   * Escape HTML so remote release notes can never inject markup.
   */
  function escapeHtml(text) {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function inlineMarkdown(escaped) {
    return escaped
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`([^`]+)`/g, '<code>$1</code>');
  }

  /**
   * Render release notes with a tiny, escaping-first markdown subset.
   * Input is escaped before any tag is added, so only this function's own
   * markup can reach the DOM.
   */
  function simpleMarkdown(text) {
    if (!text) {
      return '<p>No release notes provided for this build.</p>';
    }
    const lines = escapeHtml(text.replace(/\r\n/g, '\n')).split('\n');
    let html = '';
    let inList = false;
    for (const line of lines) {
      const bullet = line.match(/^\s*[-*]\s+(.*)$/);
      if (bullet) {
        if (!inList) {
          html += '<ul>';
          inList = true;
        }
        html += `<li>${inlineMarkdown(bullet[1])}</li>`;
        continue;
      }
      if (inList) {
        html += '</ul>';
        inList = false;
      }
      const heading = line.match(/^(#{1,4})\s+(.*)$/);
      if (heading) {
        const tag = heading[1].length <= 2 ? 'h3' : 'h4';
        html += `<${tag}>${inlineMarkdown(heading[2])}</${tag}>`;
        continue;
      }
      if (!line.trim()) continue;
      html += `<p>${inlineMarkdown(line)}</p>`;
    }
    if (inList) html += '</ul>';
    return html;
  }

  function applyReleaseData(release) {
    const tagName = release.tag_name || DEFAULT_VERSION;
    const notes = release.body || '';

    let apkAsset = null;
    let ipaAsset = null;
    if (Array.isArray(release.assets)) {
      apkAsset =
        release.assets.find((asset) => asset.name && asset.name.endsWith('.apk') && asset.name.includes('-')) ||
        release.assets.find((asset) => asset.name && asset.name.endsWith('.apk'));
      ipaAsset = release.assets.find((asset) => asset.name && asset.name.endsWith('.ipa'));
    }

    const apkUrl = apkAsset ? apkAsset.browser_download_url : CANONICAL_APK_URL;
    const apkFilenameText = apkAsset ? apkAsset.name : 'Tabby.apk';
    const apkSizeText = apkAsset ? formatBytes(apkAsset.size, DEFAULT_APK_SIZE) : DEFAULT_APK_SIZE;
    const ipaUrl = ipaAsset ? ipaAsset.browser_download_url : CANONICAL_IPA_URL;
    const ipaSizeText = ipaAsset ? formatBytes(ipaAsset.size, DEFAULT_IPA_SIZE) : DEFAULT_IPA_SIZE;

    apkDownloadBtns.forEach((button) => {
      button.setAttribute('href', apkUrl);
      button.setAttribute('download', apkFilenameText);
    });

    ipaDownloadBtns.forEach((button) => {
      button.setAttribute('href', ipaUrl);
    });

    versionTags.forEach((element) => {
      element.textContent = tagName;
    });

    releaseDates.forEach((element) => {
      element.textContent = formatDate(release.published_at);
    });

    apkSizes.forEach((element) => {
      element.textContent = apkSizeText;
    });

    ipaSizes.forEach((element) => {
      element.textContent = ipaSizeText;
    });

    apkFilenames.forEach((element) => {
      element.textContent = apkFilenameText;
    });

    liveStatusTexts.forEach((element) => {
      element.textContent = `Latest build: ${tagName} (Live)`;
    });

    if (changelogBody) {
      changelogBody.innerHTML = simpleMarkdown(notes);
    }

    try {
      localStorage.setItem('tabby_latest_release', JSON.stringify({
        data: release,
        timestamp: Date.now(),
      }));
    } catch (error) {
      // Storage can be unavailable in private or restricted contexts.
    }
  }

  async function fetchLatestRelease() {
    try {
      const cached = localStorage.getItem('tabby_latest_release');
      if (cached) {
        const { data, timestamp } = JSON.parse(cached);
        if (Date.now() - timestamp < 300000) {
          applyReleaseData(data);
        }
      }
    } catch (error) {
      // Ignore a stale or malformed cache.
    }

    try {
      const response = await fetch(`${RELEASES_API_URL}?t=${Date.now()}`, {
        headers: { Accept: 'application/vnd.github.v3+json' },
        cache: 'no-store',
      });
      if (!response.ok) {
        throw new Error(`Release API returned status ${response.status}`);
      }
      const release = await response.json();
      applyReleaseData(release);
    } catch (error) {
      console.warn('[Tabby] Release sync unavailable; canonical download URLs stay active.', error);
      apkDownloadBtns.forEach((button) => {
        if (!button.getAttribute('href') || button.getAttribute('href') === '#') {
          button.setAttribute('href', CANONICAL_APK_URL);
        }
      });
      ipaDownloadBtns.forEach((button) => {
        if (!button.getAttribute('href') || button.getAttribute('href') === '#') {
          button.setAttribute('href', CANONICAL_IPA_URL);
        }
      });
      liveStatusTexts.forEach((element) => {
        element.textContent = 'Always serving the newest build';
      });
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
