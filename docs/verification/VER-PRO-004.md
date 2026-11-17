# VER-PRO-004 — Acknowledged appearance, fixed PHP English and system reduced motion

```json verification-metadata
{
  "id": "VER-PRO-004",
  "task_ids": [
    "PRO-004"
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
  "timestamp": "2026-11-01T14:17:14.656Z",
  "tested_commit": "118926f40e2eb8bf38f5cbe6134d1ab540847c76",
  "dirty_tree": true,
  "environment": "Windows; Flutter3.47.8/Dart, synthetic account/storage/widget fixtures; JDK Android debug packaging and JavaScript web compilation. No physical/emulated device, live backend, real financial data or deployment.",
  "commands": [
    "flutter test test/features/appearance_preferences_test.dart test/features/profile_settings_behavior_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "flutter build web",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 118926f",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite passed 547/547 (27 new regressions); focused appearance/settings passed 30/30; Dart analysis clean. Android debug APK and JavaScript web builds passed. Regressions cover persistence failure/retry/restart, scoped legacy normalization, queued writes, account changes, optional read corruption, contrast ratios, core light/dark screens, QR quiet zones, actual app live theme/system accessibility, zero modal transitions and production mascot stopping. Synthetic profile screenshots inspected for surfaces/colors; test fonts do not prove typography.

## Evidence

[Appearance regressions](../../test/features/appearance_preferences_test.dart), [atomic appearance storage](../../lib/core/services/appearance_preferences.dart), [semantic palette](../../lib/core/theme/tabby_palette.dart), [theme](../../lib/core/theme/tabby_theme.dart), [motion policy](../../lib/core/theme/motion_preferences.dart), [app integration](../../lib/main.dart). Local ignored screenshot artifacts contain synthetic fixtures only.

## Limits and next action

Source/widget/build evidence only. Device acceptance and production-font visual review remain required; no SQL/deployment/publication.
