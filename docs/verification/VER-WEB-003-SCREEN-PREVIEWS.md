# VER-WEB-003-SCREEN-PREVIEWS - Landing screenshot previews

```json verification-metadata
{
  "id": "VER-WEB-003-SCREEN-PREVIEWS",
  "task_ids": [
    "WEB-003"
  ],
  "timestamp": "2026-11-19T09:50:01+08:00",
  "tested_commit": "6451cfa83edbf1865f7594cc6f757a528551e9a2",
  "dirty_tree": false,
  "environment": "Windows Node and headless Brave at 1440 by 1000 and 390 by 844 and Vercel production",
  "commands": [
    "node test/web_landing_test.js",
    "Independent Brave DevTools check against local HTTP",
    "Vercel deployment status via GitHub commit status",
    "SHA-256 comparison of production HTML, CSS, JavaScript and three screenshots",
    "Independent Brave DevTools check against the production site"
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

Home, Tab details and Dark mode select their matching Tabby screenshot and caption. Selection starts a crossfade and leaves the image viewport the same size. Arrow keys move selection, active tab semantics and focus together. The Node check covers click, arrow, Home and End navigation, landing mirrors, release downloads and the live shell. Independent Brave checks covered click, crossfade, arrow navigation, no horizontal overflow, real image decoding and reduced motion on both desktop and mobile. With JavaScript disabled, all three screenshots were visible.

## Evidence

The edited files retain the existing download aliases, navigation and assets. The page mirrors are byte-identical. [Feature tabs reference](https://brewedops.cloud/motionlibrary/?id=cards-feature-tabs).

## Limits and next action

Vercel tabby-web and tabby-app deployment checks succeeded for `6451cfa83edbf1865f7594cc6f757a528551e9a2`. The public HTML, CSS, JavaScript and all three screenshot assets matched the reviewed bytes. Brave repeated the normal and reduced-motion interactions at both viewport sizes. Non-Chromium browser acceptance is pending. [Live Screens](https://tabby-web-fawn.vercel.app/#screens).
