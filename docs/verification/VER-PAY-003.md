# VER-PAY-003 — Durable append-only receipt revisions

```json verification-metadata
{
  "id": "VER-PAY-003",
  "task_ids": [
    "PAY-003"
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
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T18:44:23.408Z",
  "tested_commit": "eb76300bde3a024f1f2832e90f4d4c2f39174ce0",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; secure-storage/connectivity mocks; native PostgreSQL 17.11 and PGlite financial migration subset with minimal synthetic storage.objects, injected roles/JWT. No live Supabase or Android device.",
  "commands": [
    "flutter test",
    "flutter test test/features/receipt_revisions_test.dart test/features/payment_proof_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite passed 339/339; final receipt/payment focused suite passed 9/9 after upload fallback refinement; Dart analysis clean. Native PostgreSQL 17.11 and PGlite passed revision replay/conflict, original receipt retention, member read, outsider denial and referenced-object protection. Existing financial/group/payment concurrency checks still pass.

## Evidence

[Receipt regressions](../../test/features/receipt_revisions_test.dart) cover owned bytes, owner isolation, durable queue/cache history, server parsing, explicit target mapping after sync and actual decoded synthetic PNG preview. [Migration](../../supabase/migrations/20261101000002_expense_receipt_revisions.sql) and [SQL harness](../../scripts/test-money-commands.cjs) preserve original receipts, append revisions and enforce role/object boundaries. Tests use no private user images.

## Limits and next action

Source migrations are not deployed. Full Supabase inventory/services/HTTP, Android storage durability and picker lifecycle remain unverified; local encrypted-blob retention/scale remain open. No release approval.
