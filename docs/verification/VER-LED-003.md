# VER-LED-003 — Durable financial commands

```json verification-metadata
{
  "id": "VER-LED-003",
  "task_ids": [
    "LED-001",
    "LED-002",
    "LED-003",
    "LED-004"
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
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T13:17:07.092Z",
  "tested_commit": "c0a7132249efb911df772d4682af8bd2bfa98f2a",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; bundled Dart; PGlite 0.5.14 (PostgreSQL/WASM, isolated in-memory database); current dirty patch over the stated checkpoint.",
  "commands": [
    "flutter test",
    "dart analyze --fatal-infos",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base c0a7132249efb911df772d4682af8bd2bfa98f2a",
    "git diff --check"
  ]
}
```

## Expected and actual results

Flutter full suite passed 268/268, analysis has no issues. Local SQL suite passed with real source financial tables, allocation validators, balance functions and atomic RPCs plus the new migration. Discarded response then repeated/parallel API calls return one ID; changed payload/kind conflicts; actors cannot overwrite each other; failed financial validation rolls back operation reservation; payment replay after confirmation reuses the same row. Effective client roles cannot call unchecked/legacy functions or insert directly. Flutter regressions exercise frozen payload, durable-intent requirement, queue conflicts, exact result mapping/cache reload, immutable relationship namespaces and server confirmation authority.

## Evidence

Source contract migration subset: core schema, RLS, balance functions, 20261029 atomic/participant/integrity migrations and both 20261031 migrations. PGlite injects auth.uid() subject and roles; native extension provisioning is omitted. Actual public financial SQL executes, not string assertions. Output: MONEY_COMMAND_CONTRACT_OK. Focused Flutter suite 49/49 preceded full 268/268.

## Limits and next action

The SQL harness is not the entire Supabase migration inventory and has one serialized PostgreSQL connection. Concurrent independent sessions, real HTTP response loss, full fresh/upgrade install, production grants, storage, Realtime and device process death remain unverified. No source migration deployed. Legacy financial clients must upgrade; review installed versions before staging. Legacy queued writes without explicit local identity are retained as needsAttention to avoid replaying a possible historical commit. UI/manual resolution remains open. Run staging migrations and real multi-session acceptance before marking task verified/complete. Local test success does not prove absence of all bugs.
