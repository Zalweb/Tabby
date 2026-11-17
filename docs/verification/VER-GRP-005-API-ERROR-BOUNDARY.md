# VER-GRP-005-API-ERROR-BOUNDARY — normalized malformed-currency responses

```json verification-metadata
{
  "id": "VER-GRP-005-API-ERROR-BOUNDARY",
  "task_ids": ["GRP-005", "QA-001"],
  "tasks": ["GRP-005", "QA-001"],
  "tested_commit": "1c1406b2f309b6f7b67bccfb21ca8bac7ef2d987",
  "dirty_tree": true,
  "timestamp": "2026-11-04T07:10:00+08:00",
  "agent": "Codex root / Windows",
  "platform": "Windows; PostgreSQL 17.11 and PostgREST 16.5 on loopback",
  "environment": "Disposable local fresh-install and reconstructed-upgrade databases; separate synthetic accounts with self-issued JWTs; no live/Auth-issued requests",
  "commands": [
    "node .dart_tool/native-db/qa001-local-api-additional.mjs",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-m2-schema-snapshot.cjs",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub"
  ],
  "checks": [
    {"category": "fresh-local-migrations", "outcome": "passed"},
    {"category": "reconstructed-local-upgrade", "outcome": "passed"},
    {"category": "grp-005-malformed-currency-http", "outcome": "passed"},
    {"category": "other-local-postgrest-assertions", "outcome": "passed"},
    {"category": "native-postgresql-harness", "outcome": "passed"},
    {"category": "schema-all-m2-snapshot", "outcome": "passed"},
    {"category": "flutter-analysis", "outcome": "passed"},
    {"category": "flutter-suite", "outcome": "passed"},
    {"category": "live-backend-auth-issued", "outcome": "unverified"}
  ],
  "result": "local_pass_external_gates_open",
  "limitations": [
    "50 repository migrations applied fresh in local PostgreSQL 17.11 (965 statements); the reconstructed local baseline applied 32 pending files (493 statements); no migration was applied to production",
    "four client-facing M1 currency paths were exercised through PostgREST; M2 wrappers were migrated but their flags remained disabled and the M2 paths were not exercised",
    "local JWTs were self-issued; no Auth-issued/live authorization claim",
    "QA-001 remains in_progress; REL-001 open; M2 rollout disabled; emulator, live Supabase, signing and publication untouched"
  ]
}
```

## Expected and actual results

The additive migration `20261104000002_normalize_currency_api_errors.sql` wraps the client-facing JSON RPC entry points and maps PostgreSQL invalid-text/range errors to SQLSTATE/PostgREST code `PT400`, HTTP 400, and the stable message `Invalid financial input. Enter amounts as whole centavos and check the submitted values.` The response has `details: null` and `hint: null`; it contains no `22P02`, `22003`, bigint/type wording, driver text, or constraint name.

Authenticated local HTTP cases covered `create_expense_v1` (`abc.50`), `submit_payment_v1` (`1.234`), `submit_payment_v2` (overflow), and `record_received_payment_v1` (`2e3`). All four returned HTTP 400 / `PT400` with the identical body. The malformed expense transaction count stayed zero before and after; payment rows stayed zero. The local group/privacy HTTP run had 10/10 named assertions pass. M2 flags stayed false; corresponding M2 RPCs received the same wrapper but were not invoked.

The harness freshly applied all 50 repository migration files / 965 statements and upgraded the reconstructed 18-migration baseline with 32 pending files / 493 statements. Both completed without SQL errors. The native PostgreSQL harness passed, the consolidated schema snapshot test passed, Flutter analysis reported no issues, and the full Flutter suite passed 651/651.

## Limits and next action

This evidence is local only. Auth-issued/live PostgREST authorization, production migration and deployment, real-device flows, signing, and publication remain open. Keep GRP-005 `implemented` and QA-001 `in_progress`; no production or live Supabase mutation was performed.

## Evidence

The local runner emitted the 50-file fresh-install, reconstructed-upgrade, inventory and HTTP assertion results to the ignored `.dart_tool/native-db/qa001-exact-rehearsal-report.json`. The committed harness and permanent assertions are in [local-m1-http-regressions.mjs](../../scripts/local-m1-http-regressions.mjs); the additive source and synchronized consolidated snapshot are `supabase/migrations/20261104000002_normalize_currency_api_errors.sql` and `supabase/schema_all.sql`.
