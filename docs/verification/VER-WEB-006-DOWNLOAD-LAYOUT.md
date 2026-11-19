# WEB-006 - Narrow download and legal layouts

```json verification-metadata
{
  "id": "VER-WEB-006-DOWNLOAD-LAYOUT",
  "task_ids": ["WEB-006"],
  "timestamp": "2026-11-19T13:34:45+08:00",
  "tested_commit": "42f61ef3f1dd567df1e7248d0a03fe6a8e800670",
  "dirty_tree": false,
  "environment": "Windows, Node 26, headless Brave Chromium and local static serving of the landing worktree, live Vercel baseline",
  "commands": ["node --test test/web_landing_test.js", "Chromium geometry audit at 320x640, 390x844, 800x1024 and 1440x900", "Full public APK and IPA downloads with SHA-256 comparison to release notes"],
  "checks": [{"category": "regression", "outcome": "passed"}, {"category": "ui-review", "outcome": "passed"}, {"category": "live-deployment", "outcome": "passed"}]
}
```

## Expected and actual results

The 320px public landing initially had 1px of horizontal document overflow. The rotated hero phone extended to 320.84px. Privacy and Terms overflowed 10px each at the persistent download action. The same public routes fit 390px, 800px and 1440px.

The local candidate has zero horizontal document overflow on the landing and both legal pages at all four widths. Both download controls remain visible and within the window and meet the 44px target measured on the landing download section. The legal header download action fits. A blocked GitHub release API preserves canonical download links. Main navigation continues to use its original separate `.site-nav` selector. CSS is the only website source change and both copies match. The web suite passes, including mirrors, content, release metadata fallback and a production uptime check.

## Evidence

[WEB-006 task](../progress/tasks/WEB-006.md), [public site](https://tabby-web-fawn.vercel.app/) and [public release](https://github.com/Zalweb/Tabby/releases/tag/v1.0.4%2B24). Chromium screenshots and geometry output are local test artifacts. The APK and IPA downloads matched each published digest.

## Limits and next action

This is Chromium layout evidence. Native mobile browser accessibility has not been verified.

## Production confirmation

2026-11-19T13:34:45+08:00 — The live CSS equals the integrated style bytes with SHA-256 `9059ae07b487f70031105c1d0bc0694ca13fe26bdf16cd7664982215f4b2b429`. Strict Chromium reruns on the production alias passed at 320, 390, 800 and 1440px. The landing and both legal pages had zero horizontal document overflow throughout. Both visible download actions retained their correct destinations. GitHub still reports `v1.0.4+24` as latest.
