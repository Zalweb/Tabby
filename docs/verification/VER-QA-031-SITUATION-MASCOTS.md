# QA-031 - Situation mascot animation

```json verification-metadata
{
  "id": "VER-QA-031-SITUATION-MASCOTS",
  "task_ids": [
    "QA-031"
  ],
  "timestamp": "2026-11-17T14:37:16.091Z",
  "tested_commit": "8ba583aa31955fbdfa5a4fcb7c6bb7bbb18166d6",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; immutable accepted18 + mascot overlay; Lenovo TB321FU API36 ARM64 4KB isolated .entrytest6; signed normal1.0.4+19 same-key install and startup",
  "commands": [
    "frozen flutter test --no-pub --concurrency=2 --timeout=2m",
    "frozen dart analyze --fatal-infos lib test integration_test",
    "16 new pose/motion/lifecycle/reduced-motion cases plus existing sprite/animation/layout cases",
    "frozen node scripts/usb-test.cjs --suite entry",
    "node --test scripts/usb-test.test.cjs",
    "six synthetic production-widget pose/welcome/Home preview renders",
    "skill-creator quick_validate repository and installed Tabby design skill",
    "frozen signed universal release build19; APK certificate/16KB structural verification; adb in-place install, pull/hash match and scoped startup check"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "animation-lifecycle",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "skill-validation",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
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

The approved five transparent supplied PNGs remain unchanged; a manifest records exact hashes, dimensions and alpha-derived bounds. Shared UI-only poses render thinking/waiting/helpful/reminder/celebrating alongside existing welcome/notebook/neutral/sleeping art, keeping a stable bottom-center fitting anchor and display-bounded decoding. Original blink sheet retains its true eye animation. New PNGs have whole-body nod/sway/breath/tilt/finite-hop motion, not invented eye/paw/tail frames. No new dependency or generated raster edit.

One shared engine serves welcome/onboarding, Home notebook, existing reminder/empty states, Add-created art-only celebration, pending/settled payment-entry details, receiving-method loading/retry, sync checking/offline/failure and404. Login pending/browser handoff waits; error is helpful. Ordinary payable/receivable uses notebook; pending payment never celebrates. All existing text/validation/account/session/financial meaning remains intact.

App/system reduced motion renders immediate untransformed still art and stops tickers. Current-route/TickerMode/lifecycle pause all controllers and sprite timers while covered/offstage/backgrounded. Celebration is a finite three-hop decay, then still, and does not replay on parent rebuild/resume.16 new behavioral cases pin actual decoded art, normalized bounds, motion matrices, pause/resume and reduced-motion/one-shot outcomes. Full853/853 and full analysis pass in the immutable accepted18+mascot-only snapshot. Final physical6/6 entry cases include actual loading of all9 pose assets, real thinking transform movement and reduced-motion stillness. Prior Google/intro/warm pages/full-form/sheet checks remain. Runner10 guards and repository/default user design-skill validation pass.

Six synthetic previews show9-pose grids and actual welcome/Home in light/dark with fixture-only Arial substitution. Representative images inspected for consistent scale/outline/no clipping/transparent backgrounds. No real owner financial screenshot or new backend/financial fixture. A standalone preview attempt to create an expense in mixed synthetic providers failed and was not accepted as evidence; business form regressions and independent art/finite-hop checks pass. First full851/853 failed obsolete Home Image.asset assertions, repaired to actual normalized notebook painter/asset; current853 supersedes them. Initial pose red proved generic blink had been used for thinking.

## Evidence

[Task](../progress/tasks/QA-031.md), [plan](../plans/situation-mascot-animation.md), [artwork/provenance](../assets/situation-mascot-artwork.md), [original PNG manifest](../../assets/branding/mascot/artwork-manifest.json), [pose/motion tests](../../test/features/mascot_pose_motion_test.dart), [native6-case contract](../../integration_test/android_google_entry_cases.json) and [updated design skill](../../.agents/skills/tabby-design/SKILL.md). Raw local logs/APKs/previews/configs stay ignored. Sanitized candidate source/results attach after actual signed installation.

## Limits and next action

QA-032 concurrently changes expense entry and has not completed its own acceptance. Normal19 is therefore reconstructed from exact accepted18 source plus only the reviewed mascot overlay; current unverified QA-032 source is preserved locally and excluded from this package. Full853 describes this frozen candidate, not a claim about the changing integrated checkout. QA-032 acknowledged build/device reservation and future20 floor. Signed universal19 build/source/installed-byte/startup acceptance is pending at record creation. Independent integration review, iOS runtime, actual screen reader and exact-candidate16KB runtime remain unverified. Real provider/payment/remote-notification acceptance is not inferred from synthetic entry cases. No public release.

2026-11-17T14:37:16.091Z - Terminal superseding evidence: signed nondebuggable universal1.0.4+19 built from immutable accepted18+mascot-only source210 hashes, with no source drift. Artifact SHA256 748fd59cb40613c6ad7932d4e6273a5716dbe16cf64390829e62add89fe77c42; approved certificate 4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a. Both ARM64/x86_64 ZIP/native16KB structural checks pass; this does not claim exact-candidate16KB runtime. Installed on Lenovo TB321FU API36 ARM64 at2026-11-17T14:33:35.151Z via adb install -r over18, firstInstallTime/certificate and existing app data preserved, no logout/financial seed. Pulled installed bytes match; launch Status: ok and current process runs without scoped fatal/loader errors. Only temporary .entrytest removed, .usbtest preserved. Build/device/source reservations released; QA-032 next normal floor20+, its functional changes preserved in checkout and excluded from19. [Sanitized results](QA-031-results.json) / [exact source](QA-031-source-manifest.json). Earlier pending sections are historical and superseded. Status remains implemented pending independent integration review; iOS/screen-reader/live backend/exact19 16KB runtime unverified. No further art needed for current whole-body motion; future independent eye/paw/tail motion needs matching frames/layers.

2026-11-17T14:38:09.403Z - Handoff repository checks: memory refresh/plain passed (86 tasks,45 findings,110 verification records). Base 8ba583aa31955fbdfa5a4fcb7c6bb7bbb18166d6 coverage exit1 has exactly24 pre-existing uncovered entries: using-superpowers skill8, supplied introduction-reference JPEGs15 and skills-lock.json1; preserved without claiming unrelated ownership. No QA-031 uncovered path. Owned diff whitespace passes. HEAD/branch remain 8ba583aa31955fbdfa5a4fcb7c6bb7bbb18166d6 / codex/m1-application-fixes; 759 dirty entries include prior/concurrent work, preserved and uncommitted. Detailed sanitized handoff checks in QA-031-results.json.
