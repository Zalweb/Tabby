# VER-PAY-001 — Specific payment decisions and concurrent confirmation

```json verification-metadata
{
  "id": "VER-PAY-001",
  "task_ids": [
    "PAY-001",
    "PAY-004"
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
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T18:09:20.800Z",
  "tested_commit": "61545a0a3f5a09d64e6ad61c6a3b1efce602ebe8",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8 with explicit storage/repository mocks; native PostgreSQL 17.11 and PGlite financial migration subset including 20261031000006; injected JWT/roles. No Supabase deployment or Android device.",
  "commands": [
    "flutter test",
    "flutter test test/features/payment_decisions_test.dart test/features/e2e_all_screens_buttons_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite 330/330 passed; focused payment decision/broad UI suite 17/17 before the additional manual-wallet regression, which is included in full suite; final analysis clean. Native PostgreSQL 17.11 and PGlite financial/group source contracts passed. Native competing confirmations admit one 4000-centavo payment against 5000 debt, reject the other, preserve both original rows, repeat decisions idempotently and confirm the exact remaining 1000 without overpayment.

## Evidence

[Flutter decisions](../../test/features/payment_decisions_test.dart), [native concurrency](../../scripts/test-backend-native.cjs), [SQL contracts](../../scripts/test-money-commands.cjs). Native test injects a 0.3-second delay before confirmed UPDATEs, launches separate recipient sessions, expects one success and one 22023 conflict, then sends eight same-ID retries. It checks original row count, audit count, payer denial, rejection reason conflict and exact final settlement. Current implementation uses actor-scoped cached results only after initiating session generation remains current. Source migration and schema_all.sql match.

## Limits and next action

Database test uses actual native SQL with synthetic JWT/role boundary and a migration subset, not all Supabase services or deployment. Flutter tests use fake repository/storage. Real network response loss, device process death and authorization across deployed accounts remain unverified. No deployment/publication; continue payment proof tasks.
