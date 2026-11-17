# VER-HOME-003 — Account-scoped notification lifecycle

```json verification-metadata
{
  "id": "VER-HOME-003",
  "task_ids": [
    "HOME-003"
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
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T04:18:45.687Z",
  "tested_commit": "4e9c0066650dd6a78e2f84ce5888152f6a7054f1",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8, JDK from Android Studio, Android debug build. Synthetic notification ports and explicit secure-storage mocks; no physical Android or live backend.",
  "commands": [
    "flutter test test/core/account_notifications_test.dart",
    "flutter test test/features/interactive_features_test.dart test/features/e2e_all_screens_buttons_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "adb devices",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 4e9c0066650dd6a78e2f84ce5888152f6a7054f1",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 407/407 and Dart analysis reported no issues. Thirteen new regressions cover scoped migration/defaults, malformed settings isolation from security loading, permission denial, delayed opt-in acknowledgment, persistence failure, category/master cancellation, forced ID collisions, duplicate/failed device writes, missing OS requests, delayed account transition and same-account new-session invalidation. Focused notification suite initially passed 12/12 before the additional persistence regression; focused existing UI suite passed 20/20 after updating obsolete default/label assertions. Android debug APK built successfully; adb reports no devices.

## Evidence

[Notification regressions](../../test/core/account_notifications_test.dart), [serialized controller](../../lib/core/services/account_notification_controller.dart), [preference store](../../lib/core/services/notification_preferences.dart), [platform service](../../lib/core/services/tabby_notification_service.dart). Synthetic callbacks prove source ordering and state behavior only. The controller probes pending OS IDs before deduplicating scheduled requests, and avoids cancelling another registered reminder through a colliding legacy ID. Original in-app notification history remains available even when device alerts are disabled.

## Limits and next action

No physical Android permission/reboot/process death/tap test or remote push integration performed. Debug build is compilation evidence only. No migration, deployment, push or publication.
