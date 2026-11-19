# VER-WEB-005-SCREENS-CAROUSEL - Screens carousel restoration

```json verification-metadata
{
  "id": "VER-WEB-005-SCREENS-CAROUSEL",
  "task_ids": [
    "WEB-005"
  ],
  "timestamp": "2026-11-19T10:09:07+08:00",
  "tested_commit": "f23e9cf324cd6c33778e968b68bc834a9f447eab",
  "dirty_tree": true,
  "environment": "Windows Node and headless Brave at 1440 by 1000 and 390 by 844",
  "commands": [
    "node test/web_landing_test.js",
    "Brave DevTools viewport, movement and reduced-motion checks",
    "git diff --check"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "production-web",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

The A look inside section again shows six app screenshots in the scrolling carousel. The Node landing suite passed. Brave decoded the six original images and measured movement on desktop and mobile. Reduced motion removed autoplay, hid the duplicate set and retained horizontal scrolling. The separate three-row feature marquee and download controls were present.

## Evidence

The restored screenshot carousel reuses the prior production assets and markup. The three docs mirrors match their landing counterparts byte for byte. The source comparison preserves the separate feature marquee and download handlers.

## Limits and next action

Publish to Vercel production and retest the deployed carousel. Browser coverage is Chromium-based.
