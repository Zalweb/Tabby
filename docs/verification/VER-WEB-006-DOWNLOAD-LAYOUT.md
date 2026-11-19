# WEB-006 - Narrow download and legal layouts

```json verification-metadata
{
  "id": "VER-WEB-006-DOWNLOAD-LAYOUT",
  "task_ids": ["WEB-006"],
  "timestamp": "2026-11-19T13:32:45+08:00",
  "tested_commit": "f2890afa71d6dc4f66c556c529af40f491b17897",
  "dirty_tree": true,
  "environment": "Windows, Node 26, headless Brave Chromium and local static serving of the landing worktree, live Vercel baseline",
  "commands": ["node --test test/web_landing_test.js", "Chromium geometry audit at 320x640, 390x844, 800x1024 and 1440x900", "Full public APK and IPA downloads with SHA-256 comparison to release notes"],
  "checks": [{"category": "regression", "outcome": "passed"}, {"category": "ui-review", "outcome": "passed"}, {"category": "live-deployment", "outcome": "unverified"}]
}
```

## Expected and actual results

The 320px public landing initially had 1px of horizontal document overflow. The rotated hero phone extended to 320.84px. Privacy and Terms overflowed 10px each at the persistent download action. The same public routes fit 390px, 800px and 1440px.

The local candidate has zero horizontal document overflow on the landing and both legal pages at all four widths. Both download controls remain visible and within the window and meet the 44px target measured on the landing download section. The legal header download action fits. A blocked GitHub release API preserves canonical download links. Main navigation continues to use its original separate `.site-nav` selector. CSS is the only website source change and both copies match. The web suite passes, including mirrors, content, release metadata fallback and a production uptime check.

## Evidence

[WEB-006 task](../progress/tasks/WEB-006.md), [public site](https://tabby-web-fawn.vercel.app/) and [public release](https://github.com/Zalweb/Tabby/releases/tag/v1.0.4%2B24). Chromium screenshots and geometry output are local test artifacts. The APK and IPA downloads matched each published digest.

## Limits and next action

Confirm that the deployed production styles match the reviewed commit and repeat the browser checks on the live alias. This is Chromium layout evidence. Native mobile browser accessibility has not been verified.
