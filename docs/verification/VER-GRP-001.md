# VER-GRP-001 — Group payment isolation and native command concurrency

```json verification-metadata
{
  "id": "VER-GRP-001",
  "task_ids": [
    "GRP-001",
    "LED-003"
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
  "timestamp": "2026-10-31T14:07:35.191Z",
  "tested_commit": "4ef8f024d77c5b36fdaef0c28e4db23d0710ceac",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; PGlite 0.5.14 and native PostgreSQL 17.11 from embedded-postgres 17.11.0-beta.19, local synthetic loopback cluster. JWT subject/roles injected; no Supabase services.",
  "commands": [
    "flutter test",
    "flutter test test/features/group_payment_parties_test.dart test/features/backend_data_handling_test.dart test/features/ledger_engine_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-money-commands.cjs",
    "node scripts/test-backend-native.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 4ef8f024d77c5b36fdaef0c28e4db23d0710ceac",
    "git diff --check"
  ]
}
```

## Expected and actual results

306/306 full Flutter tests and 52/52 focused tests passed; analysis clean. Bob-to-Carol confirmation leaves Alice at -3000, changes Bob from -3000 to -2000 and Carol from 6000 to 5000; all perspectives sum to zero. Pending/rejected payments leave balances unchanged. Cache/reload/refresh and Alice tab-detail UI preserve the same amount. Unknown recipients and a contact sharing a user ID do not credit an uninvolved user.

Both real SQL engines pass financial allocation/replay/conflict/role/contact/group contracts. Native test obtains eight distinct pg_backend_pid values, concurrently invokes the same versioned command and checks one operation registry row, one transaction and identical results, then rejects a changed payload. Native uuid-ossp/pgcrypto extension SQL executes unmodified.

## Evidence

[Flutter regressions](../../test/features/group_payment_parties_test.dart), [SQL contracts](../../scripts/test-money-commands.cjs), [native multi-session runner](../../scripts/test-backend-native.cjs). Output MONEY_COMMAND_CONTRACT_OK and NATIVE_CONCURRENCY_OK. Optional native runner leaves its uniquely named synthetic cluster under ignored .dart_tool and stops the server; it creates no host users and uses only loopback plus generated fixture credentials. Initial same-client pg concurrency warning was removed by keeping same-client replay sequential; actual concurrency uses eight independent clients.

## Limits and next action

This applies the financial migration subset, not all Supabase/auth/storage/realtime migrations. JWT subject is injected, and no HTTP network response is actually dropped. Full inventory fresh/upgrade, live policies and Android journeys remain unverified. Native concurrency evidence supersedes earlier unknown status only for same-operation replay; concurrent payment confirmation remains PAY-004. No deployment/publication.
