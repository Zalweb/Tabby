# VER-WEB-005-SCREENS-CAROUSEL - Screens carousel restoration

```json verification-metadata
{
  "id": "VER-WEB-005-SCREENS-CAROUSEL",
  "task_ids": [
    "WEB-005"
  ],
  "timestamp": "2026-11-19T10:11:28+08:00",
  "tested_commit": "eb38f11c1065327a726c5fe8856667b193ce7b9d",
  "dirty_tree": false,
  "environment": "Windows Node and headless Brave at 1440 by 1000 and 390 by 844 and live Vercel production",
  "commands": [
    "node test/web_landing_test.js",
    "Brave DevTools viewport, movement and reduced-motion checks",
    "git diff --check",
    "GitHub Vercel statuses and SHA-256 comparison of live HTML, CSS, JavaScript and all six screenshot assets",
    "Brave DevTools checks on the live desktop and mobile page"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "production-web",
      "outcome": "passed"
    }
  ]
}
```

## Expected and actual results

The A look inside section again shows six app screenshots in the scrolling carousel. The Node landing suite passed. Brave decoded the six original images and measured movement on desktop and mobile. Reduced motion removed autoplay, hid the duplicate set and retained horizontal scrolling. The separate three-row feature marquee and download controls were present.

## Evidence

The restored screenshot carousel reuses the prior production assets and markup. The three docs mirrors match their landing counterparts byte for byte. The source comparison preserves the separate feature marquee and download handlers.

## Limits and next action

Both Vercel deployments succeeded at `eb38f11c1065327a726c5fe8856667b193ce7b9d`. Public HTML, CSS, JavaScript and all six screenshots matched the reviewed files. The live desktop and phone checks passed with and without reduced motion. Browser coverage is Chromium-based. [Production Screens](https://tabby-web-fawn.vercel.app/#screens).
