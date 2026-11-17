# QA-001 local upgrade and authorization rehearsal

```json verification-metadata
{
  "id": "VER-QA-001-LOCAL-UPGRADE-AUTH",
  "task_ids": ["QA-001", "LED-003", "PAY-001", "PAY-004", "SEC-002"],
  "tested_commit": "03d53e7f1880a35f44feb46c5a551bd377b8c75f",
  "dirty_tree": true,
  "timestamp": "2026-11-04T02:21:39+08:00",
  "environment": "Windows; disposable local native PostgreSQL 17.11.0; PostgREST 16.5 on loopback",
  "checks": [
    {"category": "fresh_install", "outcome": "passed"},
    {"category": "reconstructed_baseline_upgrade", "outcome": "passed"},
    {"category": "payment_method_backfill", "outcome": "passed"},
    {"category": "local_authenticated_api_journeys", "outcome": "passed"},
    {"category": "exact_physical_baseline", "outcome": "unverified"},
    {"category": "live_backend_authorization", "outcome": "unverified"},
    {"category": "integration", "outcome": "unverified"},
    {"category": "backend-integration", "outcome": "unverified"},
    {"category": "android-device", "outcome": "unverified"}
  ],
  "commands": [
    "node .dart_tool/native-db/qa001-exact-rehearsal.mjs",
    "adb devices -l"
  ]
}
```

## Scope and safety

This run used the catalog/history snapshot previously collected from project `ziaqrkagsvozhotremsx` by SELECT-only Management API SQL. It made no requests to the live PostgREST endpoint and performed no live DDL, DML, grants, cache reload, deployment, Storage/Auth/config change, or publication change. Both databases and all API fixture rows were local disposable state. The live project was not modified.

The local upgrade starting point was reconstructed from the measured public catalog and exact 18-row `supabase_migrations.schema_migrations` snapshot. The reconstruction restored the two live-only functions, the missing reminder DELETE policy, the 10 extra realtime members, live default ACLs, and the `ensure_rls` event trigger. Its public inventory matched the captured live counts: 18 tables, 162 columns, 99 constraints, 81 indexes, 17 ordinary triggers, 42 functions, 60 policies, and 12 realtime members. The captured migration rows, including remote `statements` arrays/nulls and drifted version/name pairs, matched exactly.

This is a schema/history reconstruction, not a byte-for-byte clone. PostgreSQL physical column ordinals differ for columns in `users`, `transactions`, and `payments`; those differences do not alter the named-column contract used by the migrations, but they mean physical catalog identity is not claimed. Supabase-owned platform objects/services and production row data were not cloned. The disposable API fixture used synthetic users and ledger rows.

## Expected and actual results

PostgreSQL reported version `17.11`.

| Run | Result | Statements | Detail |
|---|---:|---:|---|
| Fresh install | PASS | 918 across all 48 migration files | No SQL error; see [prior PG17 rehearsal](VER-QA-001-PG17-REHEARSAL.md) for the complete fresh-install run. |
| Reconstructed baseline setup | PASS | 472 across 18 baseline-equivalent migration files | Baseline public inventory and recorded migration history matched the measured counts/rows above. |
| Upgrade from reconstructed baseline | PASS | 446 across 30 genuinely absent migration files | All 30 applied, final migration history count 48, no SQL error. The two September remote version IDs were reconciled to semantically identical local migration SQL and were not replayed. |

The ordered pending versions applied locally were:

`20261001000001`, `20261001000002`, `20261031000001`–`20261031000006`, `20261101000001`–`20261101000010`, and `20261102000001`–`20261102000012`.

The upgrade reached all 12 required M2 contract tables and 10 planned RPC signatures. All five reported money columns use PostgreSQL `int8` (`BIGINT`), and all four M2 feature flags (`contact_claiming`, `custom_splits`, `expense_review`, `recurring`) remained `false`.

Expected: clean application of absent migrations from the measured live baseline, preserved payment-method default semantics with revision snapshots, and member/outsider authorization matching the plan. The reconstructed-baseline upgrade, backfill assertions, and local API journeys passed as specified below. Exact physical schema identity and production acceptance remain unverified.

## Backfill assessment

Migration `20261101000004_atomic_payment_methods.sql` applied locally to six synthetic payment-method rows across three owners. Assertions passed for preserving an existing active default, choosing the earliest active fallback when no default existed, clearing an inactive former default, retaining no default when no active method existed, creating six revision-1 snapshots, and matching each snapshot to the repaired post-backfill row. No production or real-user rows were read for this test; representative data was synthetic.

## Local authenticated API journeys

PostgREST 16.5 ran against local loopback only. Generated JWT subjects exercised real PostgreSQL RLS and RPC execution with synthetic fixture accounts.

| Journey | Observed result |
|---|---|
| Member creates expense | HTTP 200; member can read the created row. |
| Outsider reads/writes expense | Read returned zero rows; write returned HTTP 403. |
| Member and outsider directly call `get_pair_outstanding` | Both returned HTTP 403 after the authorization migration. |
| Member invokes `submit_payment_v1` and retries same operation ID | HTTP 200; retry returned the same result. |
| Recipient member / outsider read payment | Member sees one row; outsider sees zero rows. |

The baseline direct helper probe allowed execution before the pending chain. After migration `20261031000001_restrict_pair_outstanding.sql`, local direct execution returned SQLSTATE `42501` (`permission denied for function get_pair_outstanding`). The migration revokes direct execution from `PUBLIC`, `anon`, and `authenticated`; wrapper execution remains available to the definer-owned financial command path. Applying version `20261031000001` is necessary to close this authorization gap in production. It was not applied to production.

## Evidence

Native PostgreSQL 17.11.0 and PostgREST 16.5 ran on Windows. The local harness emitted raw detailed inventory and per-migration/statement results in ignored `.dart_tool/native-db/qa001-exact-rehearsal-report.json`; the runner and report are intentionally not committed because the report includes captured production function/migration definitions. Sanitized result counts, version lists, and observations are recorded here.

## Limits and next action

`adb devices -l` reported zero devices. Local fixture runs are not production-authenticated acceptance. The baseline's physical column ordinal mismatch means exact physical identity remains unverified. QA-001 remains `in_progress`; M2 flags remain disabled; no deployment or release approval is implied. No production changes were made.

Obtain the approved live migration/authorization window and run the exact candidate against the live project only after its independent production change approval; separately run the Android matrix on a physical device. Until those gates actually run, retain QA-001 and REL-001 as open and keep M2 disabled.


## Subsequent local PostgREST HTTP acceptance (2026-11-04T03:44:07+08:00)

Follow-up journeys at exact source commit `c460b6d189d8b8a695541d3c9ae02b977092b08b` are recorded in [VER-QA-001-LOCAL-HTTP-ACCEPTANCE](VER-QA-001-LOCAL-HTTP-ACCEPTANCE.md). PostgreSQL 17.11 reconstructed-baseline upgrade reapplied 30 migrations without errors; PostgREST 16.5 accepted separate synthetic self-issued JWT subjects. Concurrent confirmation/overpayment, response-loss idempotency replay, contact/group share math, QR method access/update, private account isolation and payment proof/rejection journeys passed. Flutter analysis passed (71.3 seconds); full suite passed 650/650. Auth-issued JWT, live backend, Storage binary upload/signed-URL refresh and device gates remain unverified. This is local API acceptance only; no production request or mutation was made.

Response-loss replay was verified by a loopback proxy that observed PostgREST return HTTP 200 upstream and reset the client connection before forwarding a response. The retry returned the same committed transaction; changed-payload reuse returned HTTP 400.
