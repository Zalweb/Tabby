# QA-001 local PostgREST API acceptance

```json verification-metadata
{
  "id": "VER-QA-001-LOCAL-HTTP-ACCEPTANCE",
  "task_ids": ["QA-001", "PAY-004", "LED-003", "LED-004", "LED-005", "GRP-002", "GRP-003", "PAY-002", "PAY-003", "QR-001", "QR-002", "QR-003", "QR-004", "QR-005", "QR-006", "SEC-004"],
  "tested_commit": "c460b6d189d8b8a695541d3c9ae02b977092b08b",
  "dirty_tree": false,
  "timestamp": "2026-11-04T03:44:07+08:00",
  "environment": "Windows; disposable local PostgreSQL 17.11.0 reconstructed upgrade baseline; PostgREST 16.5 loopback; separate generated synthetic subjects with self-issued HS256 JWTs; Flutter 3.47.8 / Dart 3.13.7",
  "checks": [
    {"category": "local-postgrest-concurrency-and-overpayment", "outcome": "passed"},
    {"category": "local-postgrest-idempotency-replay", "outcome": "passed"},
    {"category": "local-postgrest-contact-and-group-split-math", "outcome": "passed"},
    {"category": "local-postgrest-payment-method-access-and-update", "outcome": "passed"},
    {"category": "local-postgrest-private-account-isolation", "outcome": "passed"},
    {"category": "local-postgrest-payment-proof-state-and-visibility", "outcome": "passed"},
    {"category": "flutter-analysis", "outcome": "passed"},
    {"category": "flutter-regression-suite", "outcome": "passed"},
    {"category": "storage-binary-upload", "outcome": "unverified"},
    {"category": "signed-url-expiry-refresh", "outcome": "unverified"},
    {"category": "auth-issued-jwt", "outcome": "unverified"},
    {"category": "live-backend-authorization", "outcome": "unverified"},
    {"category": "android-device", "outcome": "unverified"}
  ],
  "commands": [
    "node --check .dart_tool/native-db/qa001-local-api-additional.mjs",
    "node .dart_tool/native-db/qa001-local-api-additional.mjs",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub"
  ]
}
```

## Expected and actual results

PostgreSQL 17.11 and PostgREST 16.5 ran on loopback against a disposable reconstruction of the measured baseline, then the 30 absent migration files were applied locally. The run confirmed 18 baseline history rows/catalog counts, 30 successful pending migrations and 48 final history rows. The HTTP acceptance used separate generated synthetic account subjects and locally self-issued HS256 JWTs. These were not Supabase Auth-issued tokens and this was not live-backend acceptance. Synthetic account, tab, contact, group and Storage object metadata were seeded only in the disposable local database; acceptance writes, retries, decisions and reads were exercised through authenticated PostgREST HTTP requests.

| Journey | Expected | Observed |
|---|---|---|
| PAY-004 concurrent confirmation | Competing confirmations cannot overpay a 1,000-centavo obligation | Both 700-centavo payments submitted (HTTP 200); concurrent confirmations returned HTTP 200 and HTTP 400; one 700-centavo payment confirmed and one remained submitted. A further 301-centavo submission against the remaining 300 returned HTTP 400. |
| LED-003/LED-004 response-loss replay | Retrying the same operation ID/payload returns the original result once; changed payload conflicts | A loopback proxy let PostgREST finish the request (upstream HTTP 200), then reset the client connection before returning a response. The client observed the connection loss; retry HTTP 200 returned the same committed transaction and one matching row. Reuse with changed description returned HTTP 400. |
| LED-005 contact split | Contact party and integer-centavo shares are retained and sum exactly | API-created/read expense returned two participant rows including the unclaimed contact; shares summed to 1,001 centavos (250 + 751). |
| GRP-002 group split | Active group members and explicit shares sum exactly | API-created/read expense returned three participants; shares summed to 1,001 centavos (333 + 333 + 335). No group-as-payee settlement was exercised. |
| QR-002/QR-003 method access and update | Debtor with current debt can read the payee method; unrelated account cannot; owner update advances revision | Owner save HTTP 200; debtor read/list each returned one method; outsider read returned zero; owner replacement HTTP 200 changed the visible object path and revision 1 to 2; outsider update returned HTTP 403. |
| SEC-004 account isolation | Private owner rows are not visible in a different account session | Owner JWT read one private contact; separate subject read zero. A preliminary profile-row assertion was unsuitable because the subjects shared a tab and the connected-profile policy returned the counterpart; the corrected owner-private resource probe passed. |
| PAY-002/PAY-003 proof and decision state | Parties can read proof, outsider cannot; rejection is explicit and preserves proof without claiming confirmation | `submit_payment_v2` HTTP 200 attached a synthetic object path/reference; payer and recipient each read one proof, outsider read zero; recipient rejection HTTP 200 left status `rejected`, `confirmed_at` null and proof row retained. Storage object metadata was synthetic setup; no bytes were uploaded. |

Flutter analysis passed with `No issues found!` in 71.3 seconds. The complete Flutter suite passed **650/650**. The earlier `/transactions` or connected-profile visibility results are not substitutes for Auth/session lifecycle or live RLS acceptance.

## Evidence

The command `node .dart_tool/native-db/qa001-local-api-additional.mjs` completed successfully and printed the PostgreSQL/PostgREST versions, migration counts and compact HTTP outcomes above. For response-loss replay, a local loopback HTTP proxy observed the successful upstream response and reset the client socket before forwarding it; the client then retried directly against PostgREST. The local harness and raw reconstructed catalog report remain under ignored `.dart_tool/native-db/`; neither contains real user financial rows, and neither was committed. It used only cached read-only baseline evidence and local disposable state; this run made no live Supabase request or mutation.

## Limits and next action

These results close only the named local HTTP scenarios. They do not establish Auth-issued JWT behavior, live migration/application state or production authorization. PostgREST has no Storage binary service: object metadata was seeded locally, so actual upload/download, private-object authorization over Storage HTTP, signed URL expiry/refresh and QR image runtime were not tested. QR validation/UI, saved-method removal/default fallback, QR profile visibility, full app account-switch behavior, device flows and all 11 Android-device checks remain open. Docker/Podman are unavailable; no Supabase CLI restart was attempted. Keep QA-001 `in_progress`, REL-001 open and M2 disabled. Next: run the Auth/Storage-backed live acceptance only in an authorized disposable hosted environment, plus the physical-device matrix; production remains unchanged.
