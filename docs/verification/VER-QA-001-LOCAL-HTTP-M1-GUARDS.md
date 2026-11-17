# VER-QA-001-LOCAL-HTTP-M1-GUARDS — cancellation and reminder lifecycle regressions

```json verification-metadata
{
  "id": "VER-QA-001-LOCAL-HTTP-M1-GUARDS",
  "task_ids": ["QA-001", "CAP-006", "HOME-002", "HOME-004", "LED-005", "LED-006", "PRO-001", "PRO-003", "SEC-004"],
  "tested_commit": "da5aa3f79b7fe8a9b8dccd5642686bfca1ca2ff9",
  "dirty_tree": true,
  "timestamp": "2026-11-04T04:15:13+08:00",
  "agent": "Codex root",
  "platform": "Windows / local loopback",
  "environment": "Disposable native PostgreSQL 17.11, PostgREST 16.5 loopback, synthetic accounts and self-issued JWTs with authenticated role; Flutter 3.47.8 / Dart 3.13.7",
  "evidence_type": "local PostgREST API acceptance with self-issued JWTs plus local database and Flutter regression checks",
  "commands": [
    "node .dart_tool/native-db/qa001-local-api-additional.mjs",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/test-expense-changes.cjs",
    "node scripts/test-reminder-acceptance.cjs",
    "node scripts/test-m2-schema-snapshot.cjs",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub"
  ],
  "checks": [
    {"category":"local-postgres-fresh-install","outcome":"passed"},
    {"category":"local-postgres-reconstructed-upgrade","outcome":"passed"},
    {"category":"local-postgrest-m1-http-journeys","outcome":"passed"},
    {"category":"cap006-nondestructive-cancel-status","outcome":"passed"},
    {"category":"home002-settled-reminder-row-retained-cancelled","outcome":"passed"},
    {"category":"home004-six-hour-http-429-and-concurrent-double-tap","outcome":"passed"},
    {"category":"native-postgres-concurrency-regressions","outcome":"passed"},
    {"category":"schema-snapshot-parity","outcome":"passed"},
    {"category":"flutter-analysis","outcome":"passed"},
    {"category":"flutter-regression-suite","outcome":"passed"},
    {"category":"auth-issued-jwt","outcome":"unverified"},
    {"category":"live-backend-and-production-authorization","outcome":"unverified"},
    {"category":"android-device","outcome":"unverified"}
  ]
}
```

## Environment and scope

The ignored local harness `.dart_tool/native-db/qa001-local-api-additional.mjs` started disposable native PostgreSQL 17.11 and PostgREST 16.5 on loopback. It applied the repository migrations to a fresh database, reconstructed the previously measured local upgrade baseline, and exercised API journeys with separate synthetic subjects and self-issued HS256 JWTs using `role=authenticated`. These are local PostgREST API results, not Auth-issued or live-backend acceptance. No production/live project call or write, deployment, publication, device run, or M2 activation occurred.

## Expected and actual results

Fresh install applied all 49 repository migration files and 931 parsed SQL statements with no error. Its catalog inventory contained 46 relations, 340 columns, 125 indexes, 66 triggers, 134 functions, 109 policies, two publication members and 49 migration history rows. All four M2 flags were false. The reconstructed-upgrade run applied 31 absent files and 459 statements without error; the previously captured baseline contained 18 migration-history rows and its recorded inventory matched the live measurements used for reconstruction. This is a rehearsal only.

All 16 M1 HTTP follow-up assertions passed. In particular, the three failures from [the prior run](VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP.md) now pass:

| Task | Actual HTTP and committed-row result |
|---|---|
| CAP-006 cancellation | Request and decision returned HTTP 200. The original 800-centavo transaction remained as one row with unchanged amount and `status=cancelled`. The reasoned `EXPENSE_CHANGE_APPLIED` activity references the original; the status trigger emitted `DEBT_CANCELLED`. Cancellation creates no reversal that would double-reverse the obligation. |
| HOME-002 settled reminder | Payment submission and confirmation returned HTTP 200; refreshed balance was zero. Reminder GET returned HTTP 200 with the original reminder retained as `cancelled` (one history row). |
| HOME-004 throttle | First send and exact replay returned 200; changed payload reuse returned 400. A new operation was rejected with HTTP 429 / SQLSTATE `PT429`, with one notification row. It remained rejected at 5h59m and was accepted at 6h1s. Two concurrent requests with distinct operation IDs returned `[200, 429]` and committed one notification. |

Other local HTTP assertions remained passing: correction retained the 1,000-centavo original and append-only outputs; contact payment returned 200, committed one confirmed 300-centavo row and reduced the outstanding balance to 600; profile valid/invalid/stale-owner writes returned 200/400/403 with expected persistence; friend removal returned 200 and removed the relationship row; group archive returned 200 while retaining active shared tab and transaction; SEC-004 stale-owner request returned 403 and left the profile unchanged. Existing confirmation/overpayment, retry idempotency, 1,001-centavo split sums, QR access/update, account isolation and proof-state journeys also passed in the same harness run. LED-006's queue diagnostic and SEC-004 client-side stale-read commit suppression remain client concerns and are not claimed as server API behavior.

## Backend change

Additive migration [`20261104000001_m1_cancellation_reminder_guards.sql`](../../supabase/migrations/20261104000001_m1_cancellation_reminder_guards.sql) was applied only to the disposable rehearsals and synchronized into `supabase/schema_all.sql`. Cancellation now moves the existing transaction to `cancelled` after recording the accepted change result; it does not delete or overwrite the original amount or append a balancing reversal. A payment-status trigger marks the corresponding scheduled reminder cancelled when that payer/recipient pair settles, retaining history. The reminder RPC serializes against settlement and other sends, checks the six-hour sender/tab/recipient window server-side, and emits the stable HTTP 429 / `PT429` contract; exact operation replay is handled before throttling. The HOME plan now documents this response contract.

## Regression and Flutter checks

- `node scripts/test-backend-native.cjs` — passed on native PostgreSQL 17.11, including eight independent concurrent reminder operations: one success, seven `PT429`, one notification/audit.
- `node scripts/test-money-commands.cjs` — passed on PostgreSQL/WASM source contracts.
- `node scripts/test-expense-changes.cjs` — passed, including retained original cancellation amount/status/audit.
- `node scripts/test-reminder-acceptance.cjs` — passed, including the six-hour expiry.
- `node scripts/test-m2-schema-snapshot.cjs` — passed; consolidated snapshot matches migration sources.
- `C:\src\flutter\bin\flutter.bat analyze --no-pub` — passed, no issues found.
- `C:\src\flutter\bin\flutter.bat test --no-pub` — passed, all 650 tests.

## Evidence

The final local harness report was written to ignored `.dart_tool/native-db/qa001-exact-rehearsal-report.json`; it contains migration-level results, catalog inventories, synthetic API responses and committed-row reads. The companion console summary is `.dart_tool/native-db/qa001-m1-followup-final-run.json`. Neither contains production user data or credentials, and both remain local run outputs rather than repository evidence artifacts.

## Limits and next action

Keep CAP-006, HOME-002 and HOME-004 at `implemented`; this evidence does not establish production migration or live authorization. QA-001 remains `in_progress`, REL-001 remains open, M2 stays disabled, and live Supabase/Auth-issued acceptance plus Android device checks remain open. Do not deploy this migration from this evidence. The ignored harness report `.dart_tool/native-db/qa001-exact-rehearsal-report.json` contains the synthetic local run details and is not committed.
