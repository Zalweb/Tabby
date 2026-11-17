# VER-HOME-004 — Server-acknowledged reminder submissions

```json verification-metadata
{
  "id": "VER-HOME-004",
  "task_ids": [
    "HOME-004"
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
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T04:28:06.150Z",
  "tested_commit": "a4b7e701a5e30ced6b8f976c8e7008a1ac5e70a2",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8 with explicit storage mocks/injected reminder transport. Disposable native PostgreSQL 17.11 with eight authenticated-role sessions and PGlite PostgreSQL/WASM, synthetic JWT subject/storage fixtures and financial migration subset through 20261101000005. No Supabase HTTP/deployment or physical Android.",
  "commands": [
    "flutter test test/features/reminder_submission_test.dart test/features/tab_reminders_realtime_test.dart test/features/e2e_all_screens_buttons_test.dart",
    "flutter test test/features/reminder_submission_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base a4b7e701a5e30ced6b8f976c8e7008a1ac5e70a2",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 413/413; Dart analysis clean. Six new reminder regressions cover pending UI, provider acknowledgment order, exact server activity identity, rejected/uninvolved pairs, old-account discard, concurrent taps and restart response-loss replay. Focused earlier suite passed 24/24, followed by 6/6 new reminder suite including widget waiting/acceptance regression. Native PostgreSQL 17.11 and PostgreSQL/WASM financial source subsets passed reminder role/idempotence/rate-limit/archive checks. Eight independent native sessions return one accepted reminder and one audit row.

## Evidence

[Flutter reminder tests](../../test/features/reminder_submission_test.dart), [durable request boundary](../../lib/core/services/reminder_submission_service.dart), [native role tests](../../scripts/test-reminder-acceptance.cjs), [independent sessions](../../scripts/test-backend-native.cjs), [additive migration](../../supabase/migrations/20261101000005_reminder_acceptance.sql). Notification and audit share an explicitly assigned UUID so later activity refresh reconciles by exact identity. Failed/missing acknowledgment retains the operation ID for a user-triggered retry; no automatic offline send claims or delivery guarantees are added.

## Limits and next action

This is a verified local acknowledgment checkpoint within an unfinished HOME-004 task. Closed-app remote delivery and tap routing are not implemented by this batch. Full migration inventory, upgrades, deployed policies, Supabase HTTP, Android device and remote-service setup remain open; no deployment/publication.
