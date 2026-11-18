# WEB-001 — Landing page refresh and release sync verification

```json verification-metadata
{
  "id": "VER-WEB-001-LANDING",
  "task_ids": [
    "WEB-001"
  ],
  "timestamp": "2026-11-18T20:05:35+08:00",
  "tested_commit": "a7394bdfb5bdae53c8a24bec6f1d8addd32abae9",
  "dirty_tree": true,
  "environment": "Windows 11; Node.js v26.13.0; headless Brave (Chromium 157) against a local Python static server; Vercel production HTTP checks for `main` commit 58ee23f",
  "commands": [
    "node test/web_landing_test.js",
    "flutter test --no-pub test/features/marketing_capture_test.dart (TABBY_CAPTURE_MARKETING=true with Inter font env)",
    "headless Brave CDP navigation at 1440x1000 and 390x844",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base a7394bdfb5bdae53c8a24bec6f1d8addd32abae9",
    "node test/web_landing_test.js in a clean worktree based on 1bdf86e",
    "node scripts/check-project-memory.cjs --base 1bdf86e in the deployment worktree",
    "curl production page and cmp against landing/index.html"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "browser-layout",
      "outcome": "passed"
    },
    {
      "category": "visual-consistency",
      "outcome": "passed"
    },
    {
      "category": "release-sync",
      "outcome": "passed"
    },
    {
      "category": "deployment",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

Expected: the public landing page should adopt the Tarsi-derived warm structure while describing only current Tabby behavior, use the current mascot artwork and real current app screens, keep the release-aware download engine working for both Android and iOS, keep legal pages usable, and remain mirror-identical between `landing/` and `docs/`.

Actual:

- `node test/web_landing_test.js` passed every section: current page structure/content/assets, warm design tokens and responsive rules, release-engine and interaction setup, strict `landing/`↔`docs/` page and asset mirrors, release-data simulation, and the live Vercel shell HTTP 200 check.
- The browser loaded the page with no console or network log errors. At 1440×1000 the document had no horizontal overflow (`scrollWidth` 1425 inside a 1440 viewport with the 15px scrollbar), 23/23 images completed, all 27 reveal elements became visible after scrolling, and the header stayed sticky. At 390×844 there was no horizontal overflow (`390`/`390`), 23/23 images completed, and all 27 reveals became visible.
- The live GitHub `releases/latest` response returned HTTP 200 and the page displayed `v1.0.4+24`, released `November 18, 2026`, APK `70.2 MB`, IPA `30.2 MB`, and both versioned APK/IPA download URLs. The live status text updated to `Latest build: v1.0.4+24 (Live)`.
- Mobile navigation opened via the toggle (`aria-expanded=true`, visible panel), closed on Escape, and returned to `aria-expanded=false`. FAQ cards and the release-note `<details>` expanded natively. The release-notes body contained escaped release-note headings, paragraphs and lists and no injected `<script>`.
- Legal pages retained their dark legal hero and readable card layout at desktop and mobile widths without overflow; branding uses `assets/tabby-launcher.png`, and desktop legal navigation fits one row.
- Desktop navigation fits one row from 1021px through 1600px; the 960px breakpoint switches to the mobile menu, and 901–960px no longer wraps nav labels.
- Visual captures at desktop and mobile show the hero phone plus floating mascot, three mascot feature cards, six-screen marquee, stats/principles, offline panel, FAQ grid, dark release card, community card, and dark footer as intended.
- Deployment: `main` commit `58ee23f6c2405cbe79db3a4eaa6dfe34bc9fb42a` triggered successful Vercel production deployments for `tabby-web` and `tabby-app`. `https://tabby-web-fawn.vercel.app` returned HTTP 200 with a 34,917-byte page byte-identical to `landing/index.html`; `/app.js`, `/styles.css`, `/privacy`, `/terms`, the launcher icon, a screenshot and two mascots all returned HTTP 200.

Screenshots are local, ignored artifacts under `build_artifacts/landing-verify/` (full-page and section captures such as `desktop-full.png`, `mobile-full.png`, `final-desktop-release.png`, `final-mobile-release-top.png`, `final-mobile-changelog-open.png`, and legal-page captures). The marketing capture fixture produced `build_artifacts/marketing/{login,home,detail,profile}-{light,dark}.png` from synthetic Maria Santos data; the profile capture was not published because it contained a “Not available yet” placeholder.

Issues found and corrected during verification: the hero glow pseudo-element extended 160px beyond the hero and forced a 551px mobile layout; it is now constrained to the hero width. The desktop header wrapped “FAQ” because of the brand tagline and unconstrained buttons; the header tagline was removed, buttons are nowrap, and the mobile breakpoint is 960px. Lazy marquee screenshots could remain undecoded while offscreen; the six marquee frames now load eagerly.

## Evidence

- Test command output: all six landing verification sections passed.
- Browser session: Chromium 157 headless (Brave), local static server at `127.0.0.1:4173`; live release API `https://api.github.com/repos/Zalweb/Tabby/releases/latest` returned 200; Google Fonts loaded 200; no console or log errors.
- Captures: `build_artifacts/landing-verify/` (desktop/mobile full-page and section screenshots; `final-desktop-hero.png`, `final-desktop-release.png`, `final-desktop-community.png`, `final-desktop-footer.png`, `final-mobile-*`, `final-desktop-privacy.png`, `final-mobile-privacy.png`).
- Marketing fixture: `test/features/marketing_capture_test.dart` with `TABBY_CAPTURE_MARKETING=true`; synthetic fixtures only.

## Limits and next action

The live Vercel production site was redeployed and verified at the HTTP/page level; the interactive browser pass was performed before deployment against identical page sources, not against the production URL. This task did not publish a GitHub release, tag, app artifact or backend change. Browser coverage is local headless Chromium only: Safari, Firefox, real mobile devices, and a formal accessibility audit are unverified. Independent integration review is unverified. The marketing captures require the gated fixture and a local Inter font; normal CI does not run them. The next action is an independent integration review and an interactive live browser pass of release metadata, mobile navigation and both download buttons.

## Home dashboard landing follow-up

2026-11-18T20:56:43+08:00 — Predeployment checks passed on an isolated checkout based on `adb4662babb188aded797ddfd3a7a1d835676f38`. The landing and docs HTML matched byte for byte. Both Home images matched the fresh app captures, and the live light image already had the same SHA-256 as the reference. `node test/web_landing_test.js` passed six sections, including the existing live HTTP check. Headless Brave verified the new Home CTA, gallery target and visible content, both loaded Home screenshots and both download buttons at 1440 × 1000 and 390 × 844. Both widths fit without horizontal page overflow and all 27 reveal elements appeared. Desktop and mobile captures were visually reviewed. The initial restricted browser pass could not start DevTools; the approved repeat passed. GitHub's latest published release was `v1.0.4+24`. The private Android 25 tablet evidence is in QA-041 on the app integration branch.

## Minimal downloads and feature mascot motion

2026-11-18T21:37:18+08:00 — On the scoped clone, the hero keeps the Home screenshot and drops the waving overlay and centavo chip. The download card reduces to platform actions, requirements and concise iOS sideload guidance. The public website no longer renders release notes. All six sections of `node test/web_landing_test.js` passed, including the fetched-asset link update and original live shell. Brave at 1440 × 1000 and 390 × 844 showed all three feature images animating once with distinct motion and staying static with reduced motion. Both views fit their viewport and showed both download actions. Verified with local static HTTP and inspected desktop/mobile captures.

## Selected landing element removals

2026-11-18T23:48:24+08:00 — The owner selected and removed the How it works panel and the Recipient confirmed hero badge. Their exclusive styles and navigation links were removed. The feature cards, payment confirmation explanation and download actions remain available. The existing Node landing suite passed all six sections. Brave at 1440 and 390 pixels confirmed both removals, zero stale panel links on the landing and legal pages, zero page exceptions and no horizontal overflow. The landing and docs mirrors match byte for byte. Vercel production verification follows.
