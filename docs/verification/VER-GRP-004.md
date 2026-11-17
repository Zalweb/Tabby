# VER-GRP-004 — Atomic retry-safe group creation

```json verification-metadata
{
  "id": "VER-GRP-004",
  "task_ids": [
    "GRP-004"
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
    }
  ],
  "timestamp": "2026-10-31T14:22:09.925Z",
  "tested_commit": "f69d5e2c50d6f5e97d6b1cb0395b4eef90fcf466",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; secure-storage/widget mocks; native PostgreSQL 17.11 and PGlite financial/group migration subset with injected JWT subject and roles. No Supabase deployment/device.",
  "commands": [
    "flutter test",
    "flutter test test/features/create_tab_flow_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Flutter full suite 321/321; final create-flow retry suite 5/5; Dart analysis clean. Native PostgreSQL 17.11 and PGlite pass injected failures at five insert stages with zero partial rows, successful identical retry, conflict/duplicate/nonfriend rejection and complete rosters. Eight independent native sessions create one group per operation.

## Evidence

Actual source migration 20261031000004_atomic_group_creation.sql and synchronized schema_all.sql. [SQL harness](../../scripts/test-money-commands.cjs) attaches a failing trigger in turn to groups, group_members, tabs, tab_members and group_creation_commands, verifies every table count unchanged after each rollback, removes faults and retries the same operation. Native runner verifies eight distinct database sessions return the same group/tab and one registry row. [Flutter regression](../../test/features/create_tab_flow_test.dart) injects the first null response, checks no group/local false success and unlocked retry button, retries with the same form ID, then gets one complete group with correct expense shares.

## Limits and next action

Only the local financial/group source migration subset was applied. Full Supabase services/deployed inventory and real client upgrades remain unverified. Direct legacy multi-request group INSERT callers must upgrade to the versioned RPC; evaluate installed versions before staging. No live deployment/publication. Continue input and payment fixes.
