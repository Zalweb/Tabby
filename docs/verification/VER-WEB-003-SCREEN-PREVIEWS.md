# VER-WEB-003-SCREEN-PREVIEWS - Landing screenshot previews

```json verification-metadata
{
  "id": "VER-WEB-003-SCREEN-PREVIEWS",
  "task_ids": [
    "WEB-003"
  ],
  "timestamp": "2026-11-19T09:47:14+08:00",
  "tested_commit": "3985eb94f644bb4fbe968ca206928f9b84728282",
  "dirty_tree": true,
  "environment": "Windows Node and headless Brave at 1440 by 1000 and 390 by 844",
  "commands": [
    "node test/web_landing_test.js",
    "Independent Brave DevTools check against local HTTP"
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

Home, Tab details and Dark mode select their matching Tabby screenshot and caption. Selection starts a crossfade and leaves the image viewport the same size. Arrow keys move selection, active tab semantics and focus together. The Node check covers click, arrow, Home and End navigation, landing mirrors, release downloads and the live shell. Independent Brave checks covered click, crossfade, arrow navigation, no horizontal overflow, real image decoding and reduced motion on both desktop and mobile. With JavaScript disabled, all three screenshots were visible.

## Evidence

The edited files retain the existing download aliases, navigation and assets. The page mirrors are byte-identical. [Feature tabs reference](https://brewedops.cloud/motionlibrary/?id=cards-feature-tabs).

## Limits and next action

Publish the isolated web commit and verify the live Vercel assets and interactions. Non-Chromium browser acceptance is pending.
