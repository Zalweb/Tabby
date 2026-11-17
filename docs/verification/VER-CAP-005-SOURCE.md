# VER-CAP-005-SOURCE — Expense review local source acceptance

```json verification-metadata
{
  "id": "VER-CAP-005-SOURCE",
  "task_ids": [
    "CAP-005"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "migration-snapshot",
      "outcome": "passed"
    },
    {
      "category": "live-backend",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-04T00:12:14+08:00",
  "tested_commit": "c1e65580170774e602e4ee587d3e7eb00b591d41",
  "dirty_tree": true,
  "environment": "Windows; Flutter widget/unit tests; disposable local native PostgreSQL 17.11 with synthetic registered accounts and authenticated database roles. No live Supabase, Android device, deployment or production data.",
  "commands": [
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub test/features/expense_review_test.dart",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-m2-schema-snapshot.cjs"
  ]
}
```

## Expected and actual results

The full Flutter regression run passed **650/650**. The focused CAP-005 widget run passed **6/6**, including acknowledgment's separate-consent behavior, frozen proposal intent, resolution vote payload, legacy-status non-inference, invalid-dispute rejection and the visible open-dispute unanimous-resolution action. The added UI test confirmed that the exact transaction, dispute and resolution IDs plus explicit affirmative vote were queued for retry.

`flutter analyze --no-pub` completed with **No issues found**. The native harness started disposable PostgreSQL 17.11, applied the real financial/M2 migration subset and ran the SQL contracts under authenticated database roles. CAP-005 checks passed for creator/outsider denial, disabled rollout, immutable acknowledgment and replay, rejected proposals with no result rows or balance changes, rejected resolution remaining open, all-party resolution, unchanged source transaction JSON, operation payload conflict, and eight-session acknowledgment/final-resolution/proposal decision races. This is local SQL integration evidence with synthetic identities; it does not exercise Supabase Auth, PostgREST, Storage, realtime, deployed grants or a remote database.

The M2 migration snapshot test passed byte-for-byte comparison for all four M2 migrations, including `20261102000012_expense_review.sql`. The migration is additive and `schema_all.sql` remains synchronized. The Flutter and SQL capability gates remain false.

## Evidence

- [Expense review migration](../../supabase/migrations/20261102000012_expense_review.sql) and synchronized [schema snapshot](../../supabase/schema_all.sql).
- [Native acceptance harness](../../scripts/test-expense-review.cjs) invoked by [native PostgreSQL runner](../../scripts/test-backend-native.cjs) and [Flutter widget regressions](../../test/features/expense_review_test.dart).
- [M2 snapshot parity check](../../scripts/test-m2-schema-snapshot.cjs) and [hidden rollout constants](../../lib/features/tabs/domain/m2_capabilities.dart).

## Limits and next action

No migration was deployed. Live Supabase fresh-install/upgrade and authenticated API acceptance, real-device behavior, M1 dependency gates, independent integration review and release acceptance remain open. Keep the M2 feature hidden until those gates pass. Run the live backend and device scenarios on an authorized non-production environment, record exact environment/migration versions, then request review before changing CAP-005 from implemented to verified.

- 2026-11-04T00:12:14+08:00 — CAP-005 source verification resumed from c1e6558; local regression and native SQL integration results recorded. This record does not close external acceptance.
