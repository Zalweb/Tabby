# QA-026 — Consistent warm interface and design skill

```json verification-metadata
{
  "id": "VER-QA-026-WARM-UI",
  "task_ids": [
    "QA-026"
  ],
  "timestamp": "2026-11-17T08:50:16.794Z",
  "tested_commit": "1f8b0bb7deaa05c3602a1d41c71f194818738fba",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; Lenovo TB321FU API36 ARM64 4KB; isolated entrytest UI suite and signed normal-main1.0.4+14",
  "commands": [
    "dart analyze --fatal-infos lib test integration_test",
    "flutter test --no-pub --concurrency=2 --timeout=2m",
    "warm-design/appearance/profile/layout focused tests",
    "production-widget preview fixture with23 rendered states",
    "node --test scripts/usb-test.test.cjs",
    "node scripts/usb-test.cjs --suite entry",
    "skill-creator quick_validate.py for repository and installed skill",
    "signed ARM64 release build14; verify-android-artifact.cjs expected certificate, package, ZIP16KB/ELF checks",
    "guarded adb install -r; pull exact installed APK SHA256; native launch"
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
      "category": "visual-consistency",
      "outcome": "passed"
    },
    {
      "category": "skill-validation",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "project-memory",
      "outcome": "passed"
    },
    {
      "category": "documentation-coverage",
      "outcome": "failed"
    }
  ]
}
```

## Expected and actual results

The login/introduction cream, amber and charcoal palette now governs the shared Flutter theme and explicit page/overlay styles. Coverage includes startup/lock/recovery/setup, Home/navigation, tabs/detail/creation flows, connections/profile/settings/privacy, receiving/payment sheets, notifications and empty/error states. Page headers use the canvas rather than old saturated emerald/teal; cards/inputs have warm roles and stronger control/focus boundaries. Home uses the generated notebook mascot instead of the receipt ring. Shared controls, calendars, selection, typography and light/dark overlays use the same contract. Semantic success/error colors remain distinct; QR quiet zones, provider/image/avatar pixels stay true. Google-only flow, account/session/draft guards and integer-centavo/append-only/payment-confirmation behavior are unchanged.

Final full suite796/796 passes, including20 new warm-design cases and existing business regressions. Analysis clean. Combined focused49 and later selection/appearance47 pass; USB runner10 guards pass. Preview fixture1/1 produces23 phone/light/dark/overlay/tablet images with synthetic data. Representative previews were visually inspected; an Arial substitute for unavailable Inter/Roboto/Ahem and actual Material Icons were loaded only for host visual QA. Original QR image colors/quiet zones remain asserted by existing appearance tests.

Native isolated com.zalweb.tabby.entrytest passes all4 required cases. The added case renders Home, tabs, detail, connections, Profile, privacy and Appearance in both modes; it checks shared canvases, amber foregrounds and sheet surfaces with real device plugins. Existing cases cover real asset decode, intro navigation/encrypted acknowledgment and retry. No real Google identity, owner financial record or owner screenshot was accessed. Fixture removed after shipping. Native fixture evidence is distinct from release smoke acceptance.

The new scoped tabby-design skill exists in the repository and the user's default Codex skills directory, with matching SHA256 d2b533e83136e5fba2c24be9bfb82fa3323c3cc1bedde892adcbb935f055d96f; both quick_validate checks pass. It gives concrete semantic colors/components, mascot density, accessibility and financial/QR exceptions, without granting deployment permission. DESIGN begins with the new authority and labels prior checkpoints historical; DEC-014 supersedes the former palette/auth-only color scope. Seven affected area plans/index/USB documentation link current contracts.

Final signed normal-main1.0.4+14 build passed with no source changes during packaging. APK SHA256 b86a5aa2dfd42c5f5e2aa0d73cb74c2b820598a3cfdc9ca1c88f925af3eb286d; certificate 4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a; nondebuggable, ZIP16KB/native ELF checks pass. Six public-only Firebase/Azure client defines retained. Guarded in-place13→14 update preserved firstInstallTime and app data/session. Pulled installed bytes exactly match; launch Status: ok and process running. No main uninstall, data clear or logout. This private dirty-tree device update is not a public release.

Earlier failures and superseding fixes are retained in [results](QA-026-results.json): obsolete Profile canvas assertion; floating snackbar intercepting Security Done (initial offscreen hypothesis disproved); preview-only missing plugin handler; selected-state/avatar/field contrast findings; first build rejected after three source files were formatted during packaging. Rejected build was never installed. Final rebuild/verification above supersedes it. Four trailing font insertion spaces were formatted; whitespace now clean.

## Evidence

[Sanitized results](QA-026-results.json), [exact candidate source hashes](QA-026-source-manifest.json), [task](../progress/tasks/QA-026.md), [design/plan](../plans/consistent-warm-ui.md), [current design authority](../project/DESIGN.md), [reusable skill](../../.agents/skills/tabby-design/SKILL.md) and [native case contract](../../integration_test/android_google_entry_cases.json). Raw device logs, APKs, configuration and fixture renders remain ignored/local. No credential or owner financial data is included.

## Limits and next action

Independent integration review, iOS runtime, actual screen-reader acceptance and exact-candidate16KB runtime remain unverified. Static alignment does not prove runtime acceptance. Startup fallback follows system brightness until account appearance preferences load. Fresh Google account creation/profile completion remains QA-025's separate live gate, not inferred from these UI checks. Existing Cupertino-font, Java native-access and package_info_plus future-KGP warnings persist. Task stays implemented until required review/release gates pass; no backend deployment or public publication occurred. Preserve earlier/concurrent dirty-tree work and use a subsequent normal tablet version greater than14.


2026-11-17T08:53:03.194Z — Final handoff: memory refresh/plain pass; whitespace passes. Base coverage fails with24 pre-existing using-superpowers skill/reference/skills-lock inputs uncovered; no QA-026 implementation file uncovered. Current tree includes a newly claimed QA-027 notification-tap repair; its .usbtest session/package is preserved. Exact candidate sources have subsequent changes: lib/core/services/notification_tap_coordinator.dart,lib/core/services/tabby_notification_service.dart,lib/main.dart; delivered candidate hashes remain the recorded build snapshot. Owner main14/session intact; UI build reservation released and subsequent normal version must exceed14.
