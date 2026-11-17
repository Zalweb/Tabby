# VER-QA-001-LOCAL-GROUP-PRIVACY-HTTP — group, payment and privacy journeys

```json verification-metadata
{
  "id": "VER-QA-001-LOCAL-GROUP-PRIVACY-HTTP",
  "task_ids": ["QA-001", "GRP-001", "GRP-002", "GRP-003", "GRP-004", "GRP-005", "PAY-001", "SEC-005"],
  "tasks": ["QA-001", "GRP-001", "GRP-002", "GRP-003", "GRP-004", "GRP-005", "PAY-001", "SEC-005"],
  "tested_commit": "5e49a573a79dd661aec222346532f205369e461d",
  "dirty_tree": true,
  "timestamp": "2026-11-04T06:56:33+08:00",
  "agent": "Codex root / Windows",
  "platform": "Windows; loopback PostgreSQL 17.11 and PostgREST 16.5",
  "environment": "Disposable native PostgreSQL baseline and PostgREST HTTP only; generated synthetic accounts and self-issued JWTs for authenticated/service roles; no Auth-issued token or live project",
  "commands": [
    "node .dart_tool/native-db/qa001-local-api-additional.mjs",
    "node scripts/test-backend-native.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs",
    "node scripts/check-project-memory.cjs --base 5e49a573a79dd661aec222346532f205369e461d"
  ],
  "checks": [
    {"category": "grp-001-local-postgrest-member-payment", "outcome": "passed"},
    {"category": "grp-002-local-postgrest-share-payer-tax-service", "outcome": "passed"},
    {"category": "grp-003-local-postgrest-group-person-identity", "outcome": "passed"},
    {"category": "grp-004-local-postgrest-group-atomicity", "outcome": "passed"},
    {"category": "grp-005-local-postgrest-clear-currency-error", "outcome": "failed"},
    {"category": "pay-001-local-postgrest-confirm-once", "outcome": "passed"},
    {"category": "sec-005-local-postgrest-export-scope", "outcome": "passed"},
    {"category": "sec-005-local-postgrest-reviewed-deletion-and-counterparty", "outcome": "passed"},
    {"category": "native-postgres-concurrency-and-contracts", "outcome": "passed"},
    {"category": "local-postgres-fresh-and-reconstructed-upgrade", "outcome": "passed"},
    {"category": "auth-issued-jwt-and-live-backend", "outcome": "unverified"},
    {"category": "physical-device", "outcome": "unverified"}
  ],
  "result": "partial_pass",
  "limitations": [
    "local PostgREST HTTP with self-issued JWTs only; not Auth-issued or live-backend acceptance",
    "GRP-002 submits client-computed integer-centavo allocations; this API run does not execute the Flutter custom-split form",
    "the SEC-005 local Auth Admin soft-delete/session removal step was simulated with local fixture SQL; service review/prepare/finish RPCs were called over loopback HTTP",
    "GRP-005 returned a raw PostgreSQL bigint parse message and its permanent assertion fails closed",
    "no production or live Supabase mutation, migration, deployment, publication, signing, Storage service, M2 activation or emulator action"
  ]
}
```

## Expected and actual results

| Journey | Actual HTTP result | Committed-row result |
|---|---|---|
| GRP-001 member-to-member group payment | Submit 200; recipient confirm 200; balance reads 200 | One confirmed 1,000-centavo payment. Uninvolved member A stayed at -3,000 centavos before and after. |
| GRP-002 payer/share completeness | Expense create and participant/balance reads returned 200 for each of three payer choices | Base 1,001 + tax 100 (10%) + service 50 (5%) = 1,151 centavos. Each payer choice retained exactly three shares `[383, 382, 386]`; totals and balances matched each selected payer. Tax/service were calculated into client-supplied integer shares; the RPC stores the resulting shares and total. |
| GRP-003 group identity | Group-as-payee and group-as-payer submissions both returned 400 / `P0001` | Zero payment rows committed. The server message was `Payment parties must be distinct members of the tab`. |
| GRP-004 group creation atomicity | Injected member insert failure returned 400 / `P0001`; retry and exact replay returned 200 | Failure left counts unchanged: groups 3, group_members 8, tabs 21, tab_members 49, commands 0. Retry/replay returned the same group ID; final counts were 4, 10, 22, 51, and 1 respectively. |
| GRP-005 malformed currency | Returned HTTP 400 / `22P02` | Zero transaction rows committed, but response leaked raw message `invalid input syntax for type bigint: "abc.50"`; the “clear message” regression failed. This is the open fix target; no source fix was made in this tranche. |
| PAY-001 confirm once | Submit 200; first confirm 200; repeated confirm 200 | Exactly one original 500-centavo payment row remained, status `confirmed`; repeated confirmation inserted nothing. |
| SEC-005 export scope | Owner and counterpart export RPCs returned 200 | Each export contained its own `account_id`; owner contact appeared in owner's export and did not leak into counterpart's export. |
| SEC-005 reviewed deletion and counterpart access | Request 200; owner request read 200/1 row; counterpart request read 200/0 rows; service review/prepare/finish 200; after processing former-owner read 403/0 transactions; counterpart reads 200 | Local service flow finished `true`. Local Auth `deleted_at` and session cleanup were fixture SQL setup, not Auth Admin HTTP. Former counterpart still read one acknowledged 1,200-centavo expense and one confirmed 200-centavo payment; deletion request remained private. |

The final harness command exited 1 because the GRP-005 clear-error assertion failed. All other assertions passed. The run used self-issued JWTs and separate generated accounts over loopback; it is not Auth-issued or live-backend acceptance. The ignored local bootstrap harness imports the permanent assertions from [local-m1-http-regressions.mjs](../../scripts/local-m1-http-regressions.mjs). It also applied all 49 migration files / 931 statements on a fresh PostgreSQL 17.11 database and applied 31 pending files / 459 statements on the reconstructed local upgrade baseline without migration errors; all four M2 feature flags remained false.

## Evidence

The ignored local harness report `.dart_tool/native-db/qa001-exact-rehearsal-report.json` contains the sanitized synthetic API results and row counts. No production credentials or financial data were used. The committed regression helper records a named pass/fail assertion per behavior and the harness exit condition fails when an assertion fails.

`node scripts/test-backend-native.cjs` also passed on local PostgreSQL 17.11, including the group atomicity, payment decision/idempotency and concurrent financial/social contract checks. This is native local SQL evidence, not HTTP, Auth-issued, Storage service or live deployment evidence.

## Limits and next action

Keep all tasks `implemented`. Fix GRP-005 with a clear validation error before bigint conversion in a separately scoped change, then rerun the same assertion. SEC-005 processing in this local harness proves database/service RPC behavior only; Auth Admin, deployed Edge Function, Storage removal and Auth-issued token invalidation remain unverified. QA-001 remains `in_progress`, REL-001 open, M2 disabled. No live Supabase action or device claim is made.
