# VER-GRP-003 — Actual-member group settlement

```json verification-metadata
{
  "id": "VER-GRP-003",
  "task_ids": [
    "GRP-003"
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
    }
  ],
  "timestamp": "2026-10-31T14:18:37.041Z",
  "tested_commit": "6a487551e31e60ca970a1d305532ecaebf399b6c",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; widget/provider/cache tests with injected method repository; PostgreSQL 17.11 native and PGlite financial migration subset/JWT-role fixture. No deployed Supabase or Android device.",
  "commands": [
    "flutter test",
    "flutter test test/features/group_settlement_test.dart test/features/group_payment_parties_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite 320/320 passed; focused group settlement/isolation 7/7; analysis clean. Native PostgreSQL 17.11 and PGlite financial contracts passed, including payment of a valid pair debt when aggregate net is zero and an uninvolved member staying unchanged.

## Evidence

[Pair regressions](../../test/features/group_settlement_test.dart) open the actual PaymentMethodPaymentSheet and assert the requested tab/payee and rendered creditor method; they do not load a live private QR object. [SQL contracts](../../scripts/test-money-commands.cjs) execute actual pair-bounded submission/confirmation despite zero aggregate net and verify an uninvolved member balance. Native eight-session same-operation replay also continues to pass.

## Limits and next action

Full Supabase inventory/RLS/storage HTTP/SDK behavior and actual Android wallet QR use remain unverified. Group paths never use a group ID as payer/recipient. No historical allocations are inferred. No deployment/release. Continue group atomicity, amount validation and payment-ID lifecycle.
