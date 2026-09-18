/**
 * Tabby — Automated Release & Dynamic Download Engine + Interactive UX Animations
 * Fetches the latest published release from Zalweb/Tabby via GitHub API,
 * dynamically updates download links, and controls scroll-triggered pop animations.
 */

(function () {
  'use strict';

  const GITHUB_OWNER = 'Zalweb';
  const GITHUB_REPO = 'Tabby';
  const RELEASES_API_URL = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;
  const RELEASES_PAGE_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases`;
  const CANONICAL_APK_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download/Tabby.apk`;
  const CANONICAL_IPA_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download/Tabby.ipa`;

  // DOM Elements for Release Engine
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
    if (!isoString) return 'September 17, 2026';
    try {
      const date = new Date(isoString);
      return date.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric'
      });
    } catch (e) {
      return 'September 17, 2026';
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
    const tagName = release.tag_name || 'v1.0.2';
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

  /**
   * Setup Scroll-Triggered "Slowly Pop" Animation
   * Observes all .pop-on-scroll elements and triggers a smooth upward pop
   * and gentle scale expansion as elements enter the viewport on scroll.
   * Re-triggers when elements scroll back into view ("every scroll").
   */
  function setupScrollPopAnimations() {
    const popElements = document.querySelectorAll('.pop-on-scroll');
    if (!popElements.length) return;

    if (!('IntersectionObserver' in window)) {
      popElements.forEach(el => el.classList.add('is-visible'));
      return;
    }

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
        } else {
          // Reset when scrolled out of view so it slowly pops again on every scroll
          const rect = entry.boundingClientRect;
          if (rect.top > window.innerHeight || rect.bottom < 0) {
            entry.target.classList.remove('is-visible');
          }
        }
      });
    }, {
      root: null,
      threshold: 0.12,
      rootMargin: '0px 0px -25px 0px'
    });

    popElements.forEach(el => observer.observe(el));

    // For elements initially in viewport on page load, pop them smoothly
    requestAnimationFrame(() => {
      popElements.forEach(el => {
        const rect = el.getBoundingClientRect();
        if (rect.top < window.innerHeight - 20 && rect.bottom > 0) {
          el.classList.add('is-visible');
        }
      });
    });
  }

  /**
   * Interactive Mockup Phone Focus / Elevate
   * Enables tapping or clicking any of the 3 phones in the mockup stage
   * to focus and bring that phone to the foreground.
   */
  function setupMockupInteractivity() {
    const mockups = document.querySelectorAll('.mockup-item');
    if (!mockups.length) return;

    mockups.forEach(phone => {
      phone.addEventListener('click', (e) => {
        e.stopPropagation();
        const wasFocused = phone.classList.contains('is-focused');
        mockups.forEach(p => p.classList.remove('is-focused'));
        if (!wasFocused) {
          phone.classList.add('is-focused');
        }
      });

      // Keyboard accessibility (Enter or Space key)
      phone.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          phone.click();
        }
      });
    });

    // Dismiss focus when clicking outside the mockup stage
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.hero-mockup-stage')) {
        mockups.forEach(p => p.classList.remove('is-focused'));
      }
    });
  }

  /**
   * Setup FAQ accordion toggle
   */
  function setupFaqAccordion() {
    const faqItems = document.querySelectorAll('.faq-item');
    faqItems.forEach(item => {
      const header = item.querySelector('.faq-header');
      if (!header) return;

      header.addEventListener('click', () => {
        const isActive = item.classList.contains('active');
        faqItems.forEach(other => {
          if (other !== item) other.classList.remove('active');
        });
        item.classList.toggle('active', !isActive);
      });
    });
  }

  // Initialize on page load
  document.addEventListener('DOMContentLoaded', () => {
    fetchLatestRelease();
    setupAccordion();
    setupScrollPopAnimations();
    setupMockupInteractivity();
    setupFaqAccordion();
  });
})();
