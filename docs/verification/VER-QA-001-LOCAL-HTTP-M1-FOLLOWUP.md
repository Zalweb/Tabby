# VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP — M1 loopback API acceptance tranche

```json verification-metadata
{
  "id": "VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP",
  "task_ids": ["QA-001", "CAP-006", "LED-005", "LED-006", "PRO-001", "PRO-003", "HOME-002", "HOME-004", "SEC-004"],
  "tested_commit": "a5b216afc75889f8e6596b4e1efd8cfdba921153",
  "dirty_tree": false,
  "timestamp": "2026-11-04T03:56:19+08:00",
  "agent": "Codex root",
  "platform": "Windows / local loopback",
  "environment": "Windows; disposable PostgreSQL 17.11 reconstructed upgrade baseline; PostgREST 16.5 on loopback; synthetic subjects and self-issued HS256 JWTs; Flutter 3.47.8 / Dart 3.13.7",
  "evidence_type": "local PostgREST API acceptance with self-issued JWTs plus Flutter regression suite",
  "commands": [
    "node --check .dart_tool/native-db/qa001-local-api-additional.mjs",
    "node .dart_tool/native-db/qa001-local-api-additional.mjs",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub"
  ],
  "checks": [
    {"category":"local-postgres-reconstructed-upgrade","outcome":"passed"},
    {"category":"local-postgrest-cap006-correction","outcome":"passed"},
    {"category":"local-postgrest-cap006-cancellation-status","outcome":"failed"},
    {"category":"local-postgrest-led005-contact-payment","outcome":"passed"},
    {"category":"local-postgrest-led006-server-read","outcome":"passed"},
    {"category":"local-postgrest-pro001-profile-outcomes","outcome":"passed"},
    {"category":"local-postgrest-pro003-friend-and-archive","outcome":"passed"},
    {"category":"local-postgrest-home002-settled-reminder-row","outcome":"failed"},
    {"category":"local-postgrest-home004-six-hour-throttle","outcome":"failed"},
    {"category":"local-postgrest-sec004-expected-owner","outcome":"passed"},
    {"category":"flutter-analysis","outcome":"passed"},
    {"category":"flutter-regression-suite","outcome":"passed"},
    {"category":"auth-issued-jwt","outcome":"unverified"},
    {"category":"live-backend","outcome":"unverified"},
    {"category":"android-device","outcome":"unverified"}
  ]
}
```

## Environment and scope

The ignored native harness `.dart_tool/native-db/qa001-local-api-additional.mjs` started disposable PostgreSQL 17.11 and PostgREST 16.5 on loopback. It reconstructed the measured 18-migration local baseline from previously captured, read-only catalog evidence and then applied the 30 missing repository migrations locally. Journeys used separate synthetic identities and generated, self-issued JWTs with `role=authenticated`; they did not use Supabase Auth-issued tokens. Fixture setup SQL ran only against the disposable local database. No production or live Supabase request/write, deployment, publication, device, Storage upload, or M2 flag change occurred.

Command: `node --check .dart_tool/native-db/qa001-local-api-additional.mjs` — passed. Command: `node .dart_tool/native-db/qa001-local-api-additional.mjs` — exit 1 because three explicit contract assertions failed; the recorded API results and database reads completed. PostgreSQL upgrade rehearsal in this run applied all 30 pending migrations (48 total history rows) without migration errors.

## Expected and actual results

The run completed and captured 16 journey assertions: 13 passed and three failed. The harness exits 1 when one or more explicit contract assertions fail; this was the intended evidence result, not a migration or harness crash.

## Journey results

| Task / journey | Actual HTTP and committed-row result | Result |
|---|---|---|
| CAP-006 correction | `request_expense_change_v2` 200; reviewer `decide_expense_change_v1` 200. Original 1,000-centavo row remained `acknowledged`; an `EXPENSE_CHANGE_APPLIED` activity row linked to it; 1,000-centavo reversal and 1,200-centavo replacement were appended; change listing returned `applied`. | Pass for append-only correction/audit. |
| CAP-006 cancellation | Request 200; decision 200. Original 800-centavo row remained and retained its amount, with linked `EXPENSE_CHANGE_APPLIED` and an 800-centavo reversal; original status remained `acknowledged`. | **Fail:** required cancellation-as-status assertion expected retained row with `status=cancelled`; implementation only appends revision/reversal. The row was not deleted. |
| LED-005 contact payer / settlement | Contact cash-receipt RPC 200; one 300-centavo payment committed `confirmed` with `payer_contact_id` and recipient user populated. Balance RPC 200 returned 600 centavos remaining from 900. | Pass for contact payer and ledger balance synchronization. |
| LED-006 sync diagnostics | Authenticated `GET /transactions?select=id&limit=0` returned HTTP 200 and zero rows. No PostgREST endpoint exposes the client queue/diagnostic report; `test/features/sync_diagnostics_test.dart` ran as part of the full Flutter suite. | API data-read check passed; diagnostics acceptance is client regression evidence, not an API-level claim. |
| PRO-001 profile write | Valid update returned 200 and persisted the new display name. Invalid phone update returned 400 and left the profile unchanged. Request with JWT subject B and expected owner A returned 403 and left A unchanged. | Pass. |
| PRO-003 friend and group actions | Friend removal returned 200; accepted friendship query changed from one row to zero. Group archive RPC returned 200 and recorded the group tab in private connection preferences at revision 1; shared tab stayed `active`, and its transaction remained queryable (one row). | Pass. |
| HOME-002 settled reminder refresh | Payment submission 200; recipient confirmation 200; payment row `confirmed`; balance refresh returned HTTP 200 and zero. Reminder query returned HTTP 200 with the fixture reminder still `scheduled`. | **Fail:** settled obligation still has a scheduled reminder row at the API. This does not contradict the client-derived refresh tests; it identifies a separate persisted reminder lifecycle gap. |
| HOME-004 sent state / rate limit | First nudge returned 200 and committed one notification. Exact operation replay returned 200 without a duplicate; changed payload with same operation ID returned 400. Immediate new operation returned 400. After 61 seconds, a new operation returned 200 and a second notification was committed. | **Fail:** one-nudge-per-six-hours assertion fails; local behavior allows another nudge after about one minute. |
| SEC-004 stale account-scoped write | JWT subject B with `p_expected_owner=A` received HTTP 403 (`Account changed`); A's profile row was identical before and after. | Pass for backend expected-owner guard. Client-side late-read commit suppression is not observable through PostgREST. |

The run recorded three failed assertions: CAP-006 cancellation status, HOME-002 persisted scheduled reminder after settlement, and HOME-004 six-hour throttle. The other captured assertions passed. Failing outcomes are preserved as fix targets; no affected task was promoted to verified or complete.

## Flutter regression gates

- `C:\src\flutter\bin\flutter.bat analyze --no-pub` — passed, “No issues found!”
- `C:\src\flutter\bin\flutter.bat test --no-pub` — passed, all 650 tests.

The suite includes the client sync-diagnostics and settled-reminder regressions. These results are local automated tests, not Android-device, deployed-backend, or Auth-issued-session acceptance.

## Remaining / next action

Keep CAP-006, LED-005, LED-006, PRO-001, PRO-003, HOME-002, HOME-004, and SEC-004 at `implemented`. Fix the three failed contracts and rerun this local HTTP harness. QA-001 remains `in_progress`; REL-001 remains open. Live Supabase acceptance, Auth-issued JWT journey, real Android/device checks, and release gates remain open; M2 stays disabled. No deployment is authorized by this record.

## Evidence

The harness wrote its ignored run report under `.dart_tool/native-db/`; this non-committed output contains only disposable database and generated synthetic identity results. Exact expected and actual HTTP values and committed row outcomes are summarized in this record.

## Limits and next action

Self-issued JWTs exercise PostgREST's authenticated role but are not issued or refreshed by Supabase Auth. Local API evidence cannot close live grants/RLS, physical-device lifecycle, binary Storage, or production authorization. Preserve the three failures as the next implementation targets.
