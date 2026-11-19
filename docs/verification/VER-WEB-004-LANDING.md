# WEB-004 — Landing feature marquee verification

```json verification-metadata
{
  "id": "VER-WEB-004-LANDING",
  "task_ids": ["WEB-004"],
  "timestamp": "2026-11-19T09:55:04+08:00",
  "tested_commit": "e6dd1d93389fdfc5a4515d6959c28925e77ba592",
  "dirty_tree": false,
  "environment": "Windows, Node.js 26.13.0, headless Brave using Playwright, local static HTTP and live Vercel production",
  "commands": [
    "node test/web_landing_test.js",
    "Headless Brave Playwright wheel, responsive layout, wrap and static fallback checks",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs",
    "node scripts/check-project-memory.cjs --base 90c60b1",
    "GitHub commit status and live HTTP byte comparison with deployed Git sources"
  ],
  "checks": [
    {"category": "regression", "outcome": "passed"},
    {"category": "browser-motion", "outcome": "passed"},
    {"category": "browser-layout", "outcome": "passed"},
    {"category": "deployment", "outcome": "passed"},
    {"category": "integration-review", "outcome": "passed"}
  ]
}
```

## Expected and actual results

- The three marquee rows follow the illustrated feature cards, before Screens. The two outside rows move left and the middle moves right. The six titles match the existing principle headings. The owner requested automatic motion without a pause or resume control.
- On the deployed page at 1440 and 390 pixels, both wheel directions accelerated the rows. Over the sampled intervals, mobile leftward travel increased from 5.8 idle pixels to 13.3 during downward scrolling and 14.3 during upward scrolling. Desktop and mobile checks passed without page exceptions or horizontal overflow at those widths. Runtime reduced motion removed transforms and cloned labels, leaving six visible static titles. Returning to normal motion restarted the rows.
- Local layout checks confirmed coverage at 320, 390, 1440 and 2560 pixels after resizing. An accelerated fixture crossed 7, 7 and 10 loop boundaries with no observed gaps. Blocking the GSAP CDN or disabling JavaScript left six static titles inside the marquee. At 320 pixels the existing hero produced the same one-pixel page overflow as the prior live site. At 390 pixels with JavaScript disabled, measured overflow came from the existing header.
- The reviewed fix uses viewport observation for startup jumps, ScrollTrigger for absolute velocity and one animation-frame loop for movement. Velocity decay uses elapsed time so delayed frames do not retain the initial scroll boost. Browser runs after integration passed the immediate jump scenario. The web regression also passed screenshot-tab keyboard navigation, download links, and exact landing/docs mirrors.
## Evidence

- Both [tabby-web](https://vercel.com/zalwebs-projects/tabby-web/3tuoHmoGqEcqfeAupu5ogKuLjBL8) and [tabby-app](https://vercel.com/zalwebs-projects/tabby-app/9PpTV8S4EMpuuofNzPoxKHFMoSCE) succeeded for the deployment commit. Production home, CSS, script, Privacy and Terms returned HTTP 200 and matched committed bytes. Both pinned GSAP 3.15.0 distribution files returned HTTP 200 and matched their declared SHA-384 integrity values. [Production landing](https://tabby-web-fawn.vercel.app/#features).

## Limits and next action

Browser coverage was headless Chromium. Firefox, Safari and physical mobile browser verification remain unverified. No additional rollout step is required for the landing change.
