# VER-GRP-002 — Explicit group allocations

```json verification-metadata
{
  "id": "VER-GRP-002",
  "task_ids": [
    "GRP-002"
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
  "timestamp": "2026-10-31T14:14:34.193Z",
  "tested_commit": "46fb7170077d4287933e4c51b4380c02f6c75483",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; native PostgreSQL 17.11 financial migration subset, injected role/JWT boundary. No live Supabase/device.",
  "commands": [
    "flutter test",
    "flutter test test/features/create_tab_flow_test.dart test/features/group_expense_allocations_test.dart",
    "flutter test test/features/group_payment_parties_test.dart test/features/group_expense_allocations_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 46fb7170077d4287933e4c51b4380c02f6c75483",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite 317/317, allocation/create-flow focused suite 15/15; final group detail/allocation widget rerun passes. Analysis clean. Eight allocation scenarios exercise every payer for three/five-member 10001-centavo bills, all viewer balances, zero-sum total and exact cache roundtrip. Group default member count comes from the roster. Others-split mode assigns zero to payer and preserves total. Server parsed shares produce consistent balances across viewers. Actual form selects any member and renders exact shares; detail sheet lists each share.

## Evidence

[Allocation regressions](../../test/features/group_expense_allocations_test.dart), [detail regression](../../test/features/group_payment_parties_test.dart), [SQL contracts](../../scripts/test-money-commands.cjs). Native PostgreSQL executes actual financial functions with every payer/member perspective for three/five-member odd-cent expenses; same-operation concurrency still passes. Full suite preceded the final additive individual-share detail rendering; focused rerun and final analysis include it. Initial broad run had one obsolete payer-toggle expectation; updated to actual member picker and reran successfully.

## Limits and next action

Local database harness uses injected JWT subject and financial migration subset. It does not establish full Supabase schema/SDK/RLS deployment, real network retries or Android acceptance. Legacy group cache without roster must refresh; pending intents missing individual shares remain held for review. No deployment or release. Continue actual-member settlement and atomic group creation.
