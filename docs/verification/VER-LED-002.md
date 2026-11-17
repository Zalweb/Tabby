# VER-LED-002 — Exact activity identity reconciliation

```json verification-metadata
{
  "id": "VER-LED-002",
  "task_ids": [
    "LED-002"
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
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T19:45:57.560Z",
  "tested_commit": "8d9067b1abeef18dc151c74563f65027681323c7",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8; explicit secure-storage mocks, synthetic operation mappings and ledger/activity fixtures. No physical process death or real response-loss network.",
  "commands": [
    "dart analyze --fatal-infos",
    "flutter test test/features/activity_identity_test.dart test/features/backend_data_handling_test.dart test/features/payment_decisions_test.dart test/features/home_activity_period_test.dart",
    "flutter test",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Dart analysis clean; focused activity/backend/payment-decision/dashboard suite passed 64/64; full Flutter suite passed 383/383. Seven new regressions cover distinct same-price local/server rows, exact mapping/server precedence, interrupted checkpoint/cache reload, opaque IDs/account separation, eight concurrent mappings/conflicts, unmapped legacy rows and payment status wording.

## Evidence

[Identity regressions](../../test/features/activity_identity_test.dart) exercise actual cache APIs and serialized mapping writes. [Activity reconciliation](../../lib/features/tabs/domain/activity_reconciliation.dart) never infers identity from amounts, names or timestamps. The provider's financial result checkpoint persists mappings and strict activity-cache writes before queue removal; cache reload reuses known mappings. Existing idempotent SQL contracts are unchanged.

## Limits and next action

Synthetic checkpoint recovery is not physical crash/keystore evidence. Legacy ambiguous logs are retained, and large-history mapping retention remains open. No migration/deployment/publication.
