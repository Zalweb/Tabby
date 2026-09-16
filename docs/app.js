/**
 * Tabby — Automated Release & Dynamic Download Engine
 * Fetches the latest published release from Zalweb/Tabby via GitHub API
 * and dynamically updates APK/IPA download links, version pills, sizes, and changelogs.
 */

(function () {
  'use strict';

  const GITHUB_OWNER = 'Zalweb';
  const GITHUB_REPO = 'Tabby';
  const RELEASES_API_URL = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;
  const RELEASES_PAGE_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases`;
  const CANONICAL_APK_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download/Tabby.apk`;
  const CANONICAL_IPA_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download/Tabby.ipa`;

  // DOM Elements
  const apkDownloadBtns = document.querySelectorAll('[data-role="apk-download-btn"]');
  const ipaDownloadBtns = document.querySelectorAll('[data-role="ipa-download-btn"]');
  const versionTags = document.querySelectorAll('[data-role="version-tag"]');
  const releaseDates = document.querySelectorAll('[data-role="release-date"]');
  const apkSizes = document.querySelectorAll('[data-role="apk-size"]');
  const apkFilenames = document.querySelectorAll('[data-role="apk-filename"]');
  const liveStatusTexts = document.querySelectorAll('[data-role="live-status"]');
  const changelogBody = document.querySelector('[data-role="changelog-body"]');
  const changelogToggle = document.getElementById('changelogToggle');
  const changelogContainer = document.getElementById('changelogContainer');

  /**
   * Format bytes to readable megabytes
   */
  function formatBytes(bytes) {
    if (!bytes || isNaN(bytes)) return '68.9 MB';
    const mb = bytes / (1024 * 1024);
    return `${mb.toFixed(1)} MB`;
  }

  /**
   * Format ISO date string into readable English date
   */
  function formatDate(isoString) {
    if (!isoString) return 'September 2026';
    try {
      const date = new Date(isoString);
      return date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
      });
    } catch (e) {
      return 'September 2026';
    }
  }

  /**
   * Parse simple markdown into clean HTML safe for display
   */
  function simpleMarkdown(text) {
    if (!text) return '<p>No release notes provided for this build.</p>';
    return text
      .replace(/### (.*?)\n/g, '<h4 style="margin: 12px 0 6px; font-weight: 700; color: #1F1F1F;">$1</h4>')
      .replace(/## (.*?)\n/g, '<h3 style="margin: 16px 0 8px; font-weight: 800; color: #1F1F1F;">$1</h3>')
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`([^`]+)`/g, '<code style="background: #F3F4F6; padding: 2px 5px; border-radius: 4px; font-size: 0.85em;">$1</code>')
      .replace(/\n\n/g, '<br/><br/>')
      .replace(/\n/g, '<br/>');
  }

  /**
   * Update all DOM elements with fresh release data
   */
  function applyReleaseData(release) {
    const tagName = release.tag_name || 'v1.0.1';
    const publishedAt = formatDate(release.published_at);
    const notes = release.body || '';

    // Locate APK asset
    let apkAsset = null;
    let ipaAsset = null;

    if (Array.isArray(release.assets)) {
      // Find APK (prefer versioned name, then fallback to Tabby.apk)
      apkAsset = release.assets.find(a => a.name && a.name.endsWith('.apk') && a.name.includes('-')) ||
                 release.assets.find(a => a.name && a.name.endsWith('.apk'));

      // Find IPA
      ipaAsset = release.assets.find(a => a.name && a.name.endsWith('.ipa'));
    }

    const apkUrl = apkAsset ? apkAsset.browser_download_url : CANONICAL_APK_URL;
    const apkSizeText = apkAsset ? formatBytes(apkAsset.size) : '68.9 MB';
    const apkFilenameText = apkAsset ? apkAsset.name : 'Tabby.apk';
    const ipaUrl = ipaAsset ? ipaAsset.browser_download_url : CANONICAL_IPA_URL;

    // Update APK Download Buttons
    apkDownloadBtns.forEach(btn => {
      btn.setAttribute('href', apkUrl);
      btn.setAttribute('download', apkFilenameText);
    });

    // Update IPA Download Buttons
    ipaDownloadBtns.forEach(btn => {
      btn.setAttribute('href', ipaUrl);
    });

    // Update Version Tag Pills
    versionTags.forEach(el => {
      el.textContent = tagName;
    });

    // Update Release Dates
    releaseDates.forEach(el => {
      el.textContent = publishedAt;
    });

    // Update APK Sizes
    apkSizes.forEach(el => {
      el.textContent = apkSizeText;
    });

    // Update Filenames
    apkFilenames.forEach(el => {
      el.textContent = apkFilenameText;
    });

    // Update Live Status Badges
    liveStatusTexts.forEach(el => {
      el.textContent = `Latest Build: ${tagName} (Live)`;
    });

    // Update Changelog Body
    if (changelogBody) {
      changelogBody.innerHTML = simpleMarkdown(notes);
    }

    // Cache to localStorage for instant subsequent renders
    try {
      localStorage.setItem('tabby_latest_release', JSON.stringify({
        data: release,
        timestamp: Date.now()
      }));
    } catch (e) {
      // Storage unavailable or disabled
    }
  }

  /**
   * Fetch latest release from GitHub API with cache-busting
   */
  async function fetchLatestRelease() {
    // Check localStorage cache first for fast immediate paint
    try {
      const cached = localStorage.getItem('tabby_latest_release');
      if (cached) {
        const { data, timestamp } = JSON.parse(cached);
        // If cache is less than 5 minutes old, apply it immediately
        if (Date.now() - timestamp < 300000) {
          applyReleaseData(data);
        }
      }
    } catch (e) {}

    try {
      const response = await fetch(`${RELEASES_API_URL}?t=${Date.now()}`, {
        headers: {
          'Accept': 'application/vnd.github.v3+json'
        },
        cache: 'no-store'
      });

      if (!response.ok) {
        throw new Error(`GitHub API returned status ${response.status}`);
      }

      const release = await response.json();
      applyReleaseData(release);
      console.log(`[Tabby] Loaded latest release: ${release.tag_name}`);
    } catch (err) {
      console.warn('[Tabby] Failed to fetch latest release from GitHub API; retaining canonical fallback URLs.', err);
      // Retain canonical redirect URLs
      apkDownloadBtns.forEach(btn => {
        if (!btn.getAttribute('href') || btn.getAttribute('href') === '#') {
          btn.setAttribute('href', CANONICAL_APK_URL);
        }
      });
      ipaDownloadBtns.forEach(btn => {
        if (!btn.getAttribute('href') || btn.getAttribute('href') === '#') {
          btn.setAttribute('href', CANONICAL_IPA_URL);
        }
      });
      liveStatusTexts.forEach(el => {
        el.textContent = 'Always serving the newest build';
      });
    }
  }

  /**
   * Setup interactive changelog accordion toggle
   */
  function setupAccordion() {
    if (!changelogToggle || !changelogContainer) return;

    changelogToggle.addEventListener('click', () => {
      const isExpanded = changelogContainer.style.display !== 'none';
      changelogContainer.style.display = isExpanded ? 'none' : 'block';
      const arrow = changelogToggle.querySelector('.toggle-arrow');
      if (arrow) {
        arrow.style.transform = isExpanded ? 'rotate(0deg)' : 'rotate(180deg)';
      }
    });
  }

  // Initialize on page load
  document.addEventListener('DOMContentLoaded', () => {
    fetchLatestRelease();
    setupAccordion();
  });
})();
