# VER-PAY-002 — Payment-bound durable proof and reference

```json verification-metadata
{
  "id": "VER-PAY-002",
  "task_ids": [
    "PAY-002",
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
  "timestamp": "2026-10-31T18:25:52.891Z",
  "tested_commit": "a96f4c16e06e34ae8f5c4f982e6b088b3ca324bd",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; explicit secure-storage and widget mocks; native PostgreSQL 17.11/PGlite migration subset. Minimal synthetic storage.objects fixture and injected JWT/roles, not Supabase Storage service.",
  "commands": [
    "flutter test",
    "flutter test test/features/payment_proof_test.dart test/features/sync_retry_policy_test.dart test/features/interactive_features_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite 334/334 passed; final focused proof/queue/interactive tests passed after guard/const refinements; analysis clean. Native PostgreSQL 17.11 and PGlite pass atomic payment/proof replay, exact-object recipient read, stranger denial, immutable referenced objects and failed-proof rollback. Existing native financial/group/payment races continue to pass.

## Evidence

[Proof regressions](../../test/features/payment_proof_test.dart) create a synthetic PNG, capture it durably, delete the temporary file, reload bytes/reference, remap a pending payment target and prove frozen proof command reuse. Actual form stores reference on the payment while expense remains unchanged. [SQL harness](../../scripts/test-money-commands.cjs) executes source RPCs and policies against minimal local storage objects, checks recipient/stranger access and blocks referenced-object UPDATE/DELETE. Missing-object proof rolls back the entire payment/operation. Native eight-session financial/group/confirmation acceptance still passes. No real private user images used.

## Limits and next action

Full Supabase schema/services, HTTP object access and Android process death remain unverified. Existing expense attachment mutation is explicitly still open in PAY-003. Source migrations and schema snapshot are not deployed. No release/publication.
