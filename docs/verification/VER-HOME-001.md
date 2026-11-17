# VER-HOME-001 — Truthful dashboard totals and activity periods

```json verification-metadata
{
  "id": "VER-HOME-001",
  "task_ids": [
    "HOME-001"
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
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T19:35:55.320Z",
  "tested_commit": "b5491d3e33f8401aee33dd04c18296bb141086e5",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8; synthetic ledger/activity fixtures, fixed local clock and 390x844 widget viewport. No physical device, real timezone travel or deployed data acceptance.",
  "commands": [
    "dart analyze --fatal-infos",
    "flutter test test/features/home_activity_period_test.dart test/features/group_settlement_test.dart test/features/interactive_features_test.dart test/features/empty_state_flow_test.dart",
    "flutter test",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Dart analysis clean; initial focused dashboard/group/interactive/empty-state suite passed 20/20; final full Flutter suite passed 376/376 including the legacy-group regression and final label refinements. Nine new regressions cover rolling/calendar boundaries, UTC-equivalent instants, future exclusion, same-price IDs, zero-aggregate pair totals, submitted/confirmed payment effects, disputed/cancelled preservation, legacy review and actual dashboard filtering.

## Evidence

[Dashboard regressions](../../test/features/home_activity_period_test.dart) check exact boundaries and actual widget period changes. [Period contract](../../lib/features/home/domain/activity_period.dart) distinguishes rolling durations from local calendar month. [Dashboard state](../../lib/features/tabs/application/tabby_state.dart) retains direct group payables and receivables and flags incomplete legacy details. Disputed rows remain cached/visible while balances exclude them.

## Limits and next action

Widget viewport and synthetic UTC/local instants are not device/timezone acceptance. Older ambiguous group allocations, activity identity reconciliation and reminder correctness remain explicit open work. No deployment/publication.
