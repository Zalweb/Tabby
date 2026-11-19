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

  function setupScreenshotGalleries() {
    document.querySelectorAll('[data-screenshot-gallery]').forEach((gallery) => {
      const tabs = Array.from(gallery.querySelectorAll('[data-screen-tab]'));
      const panels = Array.from(gallery.querySelectorAll('[data-screen-panel]'));
      if (!tabs.length || tabs.length !== panels.length) return;

      const tabPanels = tabs.map((tab) => ({
        tab,
        panel: panels.find((candidate) => candidate.id === tab.getAttribute('aria-controls')),
      }));
      if (tabPanels.some(({ panel }) => !panel)) return;

      const tabList = gallery.querySelector('[role="tablist"]');
      if (tabList) tabList.hidden = false;
      gallery.classList.add('is-enhanced');

      let activeIndex = tabPanels.findIndex(({ tab }) => tab.getAttribute('aria-selected') === 'true');
      if (activeIndex < 0) activeIndex = 0;

      const setActive = (nextIndex) => {
        activeIndex = nextIndex;
        tabPanels.forEach(({ tab, panel }, index) => {
          const selected = index === activeIndex;
          tab.setAttribute('aria-selected', String(selected));
          tab.tabIndex = selected ? 0 : -1;
          panel.setAttribute('role', 'tabpanel');
          panel.setAttribute('aria-labelledby', tab.id);
          panel.setAttribute('aria-hidden', String(!selected));
          panel.tabIndex = selected ? 0 : -1;
          panel.classList.toggle('is-active', selected);
        });
      };

      const activate = (nextIndex) => {
        if (nextIndex === activeIndex) return;
        gallery.classList.add('has-selection');
        setActive(nextIndex);
      };

      setActive(activeIndex);

      tabPanels.forEach(({ tab }, index) => {
        tab.addEventListener('click', () => activate(index));
        tab.addEventListener('keydown', (event) => {
          let nextIndex;
          switch (event.key) {
            case 'ArrowRight':
              nextIndex = (index + 1) % tabs.length;
              break;
            case 'ArrowLeft':
              nextIndex = (index + tabs.length - 1) % tabs.length;
              break;
            case 'Home':
              nextIndex = 0;
              break;
            case 'End':
              nextIndex = tabs.length - 1;
              break;
            default:
              return;
          }

          event.preventDefault();
          tabs[nextIndex].focus();
          activate(nextIndex);
        });
      });
    });
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

  function setupFeatureMarquee() {
    const marquee = document.querySelector('[data-feature-marquee]');
    const motionPreference = window.matchMedia
      ? window.matchMedia('(prefers-reduced-motion: reduce)')
      : null;
    const gsap = window.gsap;
    const ScrollTrigger = window.ScrollTrigger;

    if (!marquee || !motionPreference || !gsap || !ScrollTrigger) return;

    const rows = Array.from(marquee.querySelectorAll('[data-marquee-row]'));
    if (rows.length !== 3) return;

    const rowStates = rows.map((row) => {
      const track = row.querySelector('[data-marquee-track]');
      const set = track && track.querySelector('[data-marquee-set]');
      return {
        row,
        track,
        set,
        direction: row.dataset.direction === 'right' ? 1 : -1,
        baseSpeed: Number.parseFloat(row.dataset.speed) || 22,
        phase: 0,
        period: 0,
      };
    });
    if (rowStates.some((state) => !state.track || !state.set)) return;

    let cleanup = null;

    function restoreStaticRows() {
      if (cleanup) {
        cleanup();
        cleanup = null;
      }
    }

    function enableMotion() {
      if (motionPreference.matches || cleanup) return;

      let trigger = null;
      let visibilityObserver = null;
      let useIntersectionObserver = typeof window.IntersectionObserver === 'function';
      let motionFrame = 0;
      let previousTime = null;
      let visible = false;
      let latestScrollVelocity = 0;
      let smoothedScrollBoost = 0;
      let resizeFrame = 0;
      let disposed = false;

      const placeRow = (state) => {
        const x = state.direction > 0
          ? -state.period + state.phase
          : -state.phase;
        gsap.set(state.track, { x, force3D: true });
      };

      const rebuild = () => {
        if (disposed) return;

        rowStates.forEach((state) => {
          const previousFraction = state.period > 0 ? state.phase / state.period : 0;
          state.track.querySelectorAll('[data-marquee-clone]').forEach((clone) => clone.remove());

          const period = state.set.getBoundingClientRect().width;
          const viewportWidth = state.row.clientWidth;
          if (!Number.isFinite(period) || period <= 0 || viewportWidth <= 0) return;

          state.period = period;
          state.phase = ((previousFraction % 1) + 1) % 1 * period;

          // Keep at least one full cycle beyond the viewport so wrapping stays covered
          // even when the visible row is wider than the original two-title set.
          const copies = Math.max(2, Math.ceil((viewportWidth + period * 2) / period));
          for (let index = 1; index < copies; index += 1) {
            const clone = state.set.cloneNode(true);
            clone.dataset.marqueeClone = 'true';
            clone.setAttribute('aria-hidden', 'true');
            state.track.appendChild(clone);
          }

          placeRow(state);
        });
      };

      const animate = (time) => {
        const elapsed = (time - (previousTime ?? time)) / 1000;
        previousTime = time;
        latestScrollVelocity *= Math.exp(-elapsed / 0.54);
        const requestedBoost = Math.min(latestScrollVelocity, 1800) * 0.065;
        smoothedScrollBoost += (requestedBoost - smoothedScrollBoost)
          * (1 - Math.exp(-elapsed / 0.22));

        const travelTime = Math.min(elapsed, 0.05);
        rowStates.forEach((state) => {
          if (state.period <= 0) return;
          const distance = (state.baseSpeed + smoothedScrollBoost) * travelTime;
          state.phase = (state.phase + distance) % state.period;
          placeRow(state);
        });
        motionFrame = window.requestAnimationFrame(animate);
      };

      const startMotion = () => {
        if (!motionFrame && visible) {
          motionFrame = window.requestAnimationFrame(animate);
        }
      };

      const stopMotion = () => {
        if (motionFrame) {
          window.cancelAnimationFrame(motionFrame);
          motionFrame = 0;
          previousTime = null;
        }
        latestScrollVelocity = 0;
        smoothedScrollBoost = 0;
      };

      const scheduleRebuild = () => {
        if (resizeFrame) window.cancelAnimationFrame(resizeFrame);
        resizeFrame = window.requestAnimationFrame(() => {
          resizeFrame = 0;
          rebuild();
        });
      };

      const dispose = () => {
        if (disposed) return;
        disposed = true;
        stopMotion();
        if (visibilityObserver) visibilityObserver.disconnect();
        if (trigger) trigger.kill();
        if (resizeFrame) window.cancelAnimationFrame(resizeFrame);
        window.removeEventListener('resize', scheduleRebuild);
        if (document.fonts && document.fonts.removeEventListener) {
          document.fonts.removeEventListener('loadingdone', scheduleRebuild);
        }
        rowStates.forEach((state) => {
          state.track.querySelectorAll('[data-marquee-clone]').forEach((clone) => clone.remove());
          state.track.style.removeProperty('transform');
        });
        marquee.classList.remove('is-enhanced');
      };

      try {
        gsap.registerPlugin(ScrollTrigger);
        marquee.classList.add('is-enhanced');
        rebuild();

        trigger = ScrollTrigger.create({
          trigger: marquee,
          start: 'top bottom',
          end: 'bottom top',
          onToggle: (self) => {
            if (!useIntersectionObserver) {
              visible = self.isActive;
              if (visible) {
                startMotion();
              } else {
                stopMotion();
              }
            }
          },
          onUpdate: (self) => {
            latestScrollVelocity = Math.min(Math.abs(self.getVelocity()), 1800);
          },
        });

        if (useIntersectionObserver) {
          try {
            visibilityObserver = new window.IntersectionObserver((entries) => {
              if (disposed) return;
              const isVisible = entries.some((entry) => entry.target === marquee && entry.isIntersecting);
              if (isVisible) ScrollTrigger.update();
              visible = isVisible;
              if (visible) {
                startMotion();
              } else {
                stopMotion();
              }
            }, { threshold: 0 });
            visibilityObserver.observe(marquee);
          } catch (_error) {
            if (visibilityObserver) visibilityObserver.disconnect();
            visibilityObserver = null;
            useIntersectionObserver = false;
          }
        }

        if (!useIntersectionObserver) {
          visible = trigger.isActive;
          startMotion();
        }

        window.addEventListener('resize', scheduleRebuild, { passive: true });
        if (document.fonts && document.fonts.addEventListener) {
          document.fonts.addEventListener('loadingdone', scheduleRebuild);
        }
        if (document.fonts && document.fonts.ready) {
          document.fonts.ready.then(scheduleRebuild, () => {});
        }

        return dispose;
      } catch (_error) {
        dispose();
        return () => {};
      }
    }

    const applyMotionPreference = () => {
      if (motionPreference.matches) {
        restoreStaticRows();
      } else if (!cleanup) {
        cleanup = enableMotion();
      }
    };

    if (motionPreference.addEventListener) {
      motionPreference.addEventListener('change', applyMotionPreference);
    } else if (motionPreference.addListener) {
      motionPreference.addListener(applyMotionPreference);
    }

    applyMotionPreference();
  }

  document.addEventListener('DOMContentLoaded', () => {
    fetchLatestRelease();
    setupMobileNav();
    setupHeaderState();
    setupRevealAnimations();
    setupScreenshotGalleries();
    setupFeatureMarquee();
  });
})();
