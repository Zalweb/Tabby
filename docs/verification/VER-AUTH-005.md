# VER-AUTH-005 — Adaptive onboarding and truthful draft navigation

```json verification-metadata
{
  "id": "VER-AUTH-005",
  "task_ids": [
    "AUTH-005"
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
      "category": "android-build",
      "outcome": "passed"
    },
    {
      "category": "web-build",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T05:52:45.134Z",
  "tested_commit": "dd6728a548ad76dab16883bb551b997c5be35698",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8; real Flutter widgets with synthetic account/QR fixtures, explicit storage/transport mocks and intercepted platform exit. Android Studio JDK/debug compilation; JavaScript web compilation. No physical device or live backend.",
  "commands": [
    "flutter test test/features/auth_accessibility_back_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "flutter build web",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base dd6728a",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite passed 465/465; final focused accessibility/back suite passed 14/14, including retained-draft save before platform exit. Dart analysis clean. Android debug APK and JavaScript web builds succeeded. Initial dirty-editor dialog overflow at 200 percent text was reproduced and fixed by making dialogs scrollable; initial semantics fixture teardown ordering was corrected. Native/device/backend integration was not exercised for this UI batch.

## Evidence

[Permanent widget regressions](../../test/features/auth_accessibility_back_test.dart), [adaptive onboarding](../../lib/features/onboarding/presentation/onboarding_screen.dart), [retained setup navigation](../../lib/features/auth/presentation/complete_profile_screen.dart), [wrapping buttons](../../lib/shared/widgets/tabby_button.dart). Tests cover 320x568, 568x320 and 320x480 at normal/200 percent text; login/signup/help/reset, staged receiving-method confirmation and pristine/dirty/back behavior.

## Limits and next action

Tests establish widget layouts and guarded platform calls only. Real screen-reader semantics, Android gesture exit, picker recovery and system process death require device evidence. No live backend, deployment or publication.
