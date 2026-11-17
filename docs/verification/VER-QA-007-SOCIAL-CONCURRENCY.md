# QA-007 — Canonical pair friend-request concurrency

```json verification-metadata
{
  "id": "VER-QA-007-SOCIAL-CONCURRENCY",
  "task_ids": [
    "QA-007",
    "PRO-003",
    "QA-001",
    "REL-001"
  ],
  "timestamp": "2026-11-13T18:57:37.739+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows PostgreSQL17.11 / PostgREST16.5; independent native sessions and full source SQL; injected local Auth/Storage, no actual device/provider/remote mutation",
  "commands": [
    "node scripts/test-friendship-authorization.cjs",
    "node --check scripts/test-friendship-authorization.cjs",
    "node .dart_tool/native-db/qa007-local-api.mjs (reviewed local-only rehearsal with output renamed)",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs; node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0; git diff --check"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "backend-authorization",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "fresh-upgrade",
      "outcome": "passed"
    },
    {
      "category": "schema-snapshot",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "live-backend",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "ios-device",
      "outcome": "unverified"
    },
    {
      "category": "full-platform",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

Two independent native backend sessions are paused after each has read no existing pair, by holding a temporary SHARE table lock in a third local test session. The harness observes both workers actually waiting in pg_stat_activity, then releases the barrier and awaits both terminal outcomes. This is real PostgreSQL concurrency, not PGlite or Promise scheduling alone.

Before repair, opposite directions each commit a different pending request for the same pair; the directed unique constraint allows both. Same-direction calls produce one pending row and one23505 duplicate-key failure instead of the existing-request replay result. Both failures are recorded separately before production SQL edits.

The additive repair obtains a transaction advisory lock for sorted immutable UUIDs, using a friendship-specific namespace, before the pair absence check. No row lock can protect a row that does not exist yet. Existing RPC shape, incoming-request rejection and recipient consent are preserved. No rows, directed historical records or financial history are deduplicated.

After repair, each race observes one relation wait and one advisory wait before release. Opposite calls admit one pending request and reject the second with the existing incoming-request message; same-direction calls both succeed with the same pending ID. Exactly one inbox notification and zero tab memberships are created for these pending pairs. Both directions remain pending until explicit acceptance.

All eight race cases pass across four setups:50→52 upgrade,51→52 upgrade, fresh52 migrations, standalone schema snapshot. Each case confirms two different backend PIDs. All preceding direct-insert/RLS-regrant/anonymous/private-read/recipient-accept/decline/resend/notification-link checks also pass in every setup. Final full local PostgREST rehearsal passes fresh52/52(986 statements), reconstructed upgrade34/34(514 statements),52 history rows and the existing financial/response-loss/authorization/M1/group/privacy checks. Auth/Storage and tokens retain [QA-006 limitations](VER-QA-006-FRIENDSHIP.md).

## Evidence

[Pair-lock migration](../../supabase/migrations/20261113000002_friend_request_pair_lock.sql), [native behavioral suite](../../scripts/test-friendship-authorization.cjs), [schema snapshot](../../supabase/schema_all.sql) and [source/result/log hashes](QA-007-results.json). Ignored qa007-* logs retain both original race reproductions, observed waits, final native cases and local API acceptance. 459 source hashes are recorded. All earlier migration files match QA-006 exactly; only a new migration is added. Mobile source/native configuration/tests are unchanged, so [QA-005697-test/analysis/debug evidence](VER-QA-005-SOCIAL.md) retains that scope; no new mobile run is claimed.

## Limits and next action

Production remains NO-GO; this migration is unapplied remotely. Independent integration/security/migration review, authorized effective deployed policy/history assessment and actual issued-token/Realtime/native-device/provider/signed-release acceptance remain open. Historical reverse/duplicate records are preserved; no silent cleanup or inference of consent. Continue source review, including sign-in completion awaits and optional preference failures. No live mutation, endpoint cutover, release, staging/commit or messages occurred.
