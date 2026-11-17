# VER-QR-003 — Atomic receiving method lifecycle

```json verification-metadata
{
  "id": "VER-QR-003",
  "task_ids": [
    "QR-003",
    "QR-005"
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
      "category": "backend-authorization",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T19:00:30.663Z",
  "tested_commit": "0217d7e0ec990b95f207c711ae45616f047f9c38",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8 with injected method repository/widget boundaries; native PostgreSQL 17.11 and PGlite source migration subset with synthetic auth/storage fixtures. Eight separate native backend sessions; no live Supabase/device.",
  "commands": [
    "flutter test",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 352/352; Dart analysis clean. Seven new lifecycle regressions cover nondefault preservation, failed/successful replacement, removal before successor load, failure feedback, stale-session discard and editor acknowledgment. Native PostgreSQL 17.11/PGlite passed lifecycle replay/conflict, stale-edit denial, missing-upload preservation, injected post-write rollback and immutable revisions. Eight independent native sessions serialize concurrent creation/preference and replay one operation with exactly one default.

## Evidence

[Flutter lifecycle regressions](../../test/features/payment_method_lifecycle_test.dart), [SQL lifecycle acceptance](../../scripts/test-payment-method-lifecycle.cjs) and [native concurrency](../../scripts/test-backend-native.cjs) cover the actual state and database behavior. [Migration](../../supabase/migrations/20261101000004_atomic_payment_methods.sql) repairs nonfinancial preference gaps, records revision snapshots and protects referenced old QR files. No private account/image data used.

## Limits and next action

No migrations deployed, real HTTP/image-storage fault tests or Android/two-device acceptance. Existing signed URLs retain their bearer lifetime. Draft/process-death and upload retention remain open. No release/publication.
