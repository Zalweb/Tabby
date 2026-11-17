# VER-CAP-006-BILATERAL ? Registered bilateral expense changes

```json verification-metadata
{
  "id": "VER-CAP-006-BILATERAL",
  "task_ids": [
    "CAP-006"
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
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T19:17:52.918Z",
  "tested_commit": "ce87a5d40cb426d9ee193e37b8368bffedbab540",
  "dirty_tree": true,
  "environment": "Windows; Flutter/Dart synthetic widget/storage/session fixtures; native PostgreSQL 17.11 and PostgreSQL/WASM 18.6/PGlite 0.5.14 source financial migration subsets. No live Supabase or physical device.",
  "commands": [
    "flutter test --no-pub",
    "dart analyze --fatal-infos",
    "node scripts/test-money-commands.cjs (PGlite harness loaded from existing ignored tooling)",
    "TABBY_NATIVE_DB_MODULE=<isolated tooling module> node scripts/test-backend-native.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base ce87a5d40cb426d9ee193e37b8368bffedbab540",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite passed 598/598 after final initiating-account parameters, including twelve new controller/widget/parser-cache regressions. Final Dart analysis is clean. Tests cover durable-before-network writes, storage failure blocking writes, response-loss/restart replay with the original operation ID, incompatible retry rejection, parallel suppression, late-session rejection, acknowledged-server/local-cleanup distinction, foreign history/incorrect decisions, actual request/review forms and acknowledgment ordering, editable failed saves, session hiding, protected back/discard, malformed stored drafts and existing parser/cache exact balance replay.

Native PostgreSQL and PostgreSQL/WASM source contracts passed. A 10001-centavo original (5000 payer/5001 debtor) is corrected to 7001 with exactly 3500 owed; original transaction/share JSON remains unchanged. Confirmed payment of 1000 remains unchanged, so subsequent cancellation leaves a legitimate 1000 credit/refund obligation instead of erasing payment history. Pending/rejected proposals do not alter balances. Self approval, outsider/anonymous access, changed operation payload, stale original snapshot, generated reversal changes and unsupported group/contact requests are denied. Initiating-account mismatch denies writes even when the current JWT user is the other legitimate participant.

Eight independent requester sessions replay one operation; eight reviewer sessions apply one revision. Competing different proposals for the same original admit exactly one acceptance. Existing financial/payment/group/QR/proof/reminder/profile/social contract and concurrency checks pass on the same subset. This is real local SQL role/concurrency evidence with an injected JWT boundary, not deployed Supabase acceptance.

Initial SQL fixtures incorrectly queried the other party balance (correctly denied), then compared JavaScript negative zero; corrected the harness to query the caller balance and normalize zero. A back-navigation test needed a frame after text editing so PopScope registration updated; fixed test synchronization. Initial analysis brace/private-helper infos were fixed. No source audit failure was hidden.

## Evidence

[Migration](../../supabase/migrations/20261102000004_bilateral_expense_changes.sql), [controller](../../lib/features/tabs/application/expense_changes.dart), [actual screen](../../lib/features/tabs/presentation/expense_change_screen.dart), [Flutter regressions](../../test/features/expense_changes_test.dart), [SQL acceptance](../../scripts/test-expense-changes.cjs), [native races](../../scripts/test-backend-native.cjs). Synthetic logs and local DB clusters remain under ignored .dart_tool.

## Limits and next action

This source slice supports only valid two-user individual tabs. Group/contact correction workflows remain unsupported and fail closed. Audit history requires a connection; a full offline revision-history projection is unfinished. Superseded-original reminder projection/scheduling and reporting need dedicated integration acceptance and may require further code before release. End-to-end live JWT/SDK/RLS/realtime, fresh/upgrade database provisioning and Android process/back/recovery acceptance remain unverified. No migration was applied to a live environment, no account data changed and no release artifact approved.

- 2026-11-01T19:18:47.956Z ? Final analysis initially flagged a test callback that read a wildcard parameter; renamed the callback argument. Clean analysis and focused 12/12 rerun passed; the full 598-test run already passed with the same production code.

- 2026-11-01T19:19:48.242Z ? deb45eb (codex/expense-corrections) source copied into active Tabby only after checking baseline contents of every owned path. Integrated expense-change/privacy/capability suite passed 28/28; documentation/base-coverage and whitespace checks passed. Existing terminal AND-004 cache/provider/dependency/iOS-workflow changes remain unmodified. Full 598-test and analysis evidence belongs to the isolated correction branch; no full-suite claim is inferred for concurrent terminal drafts. No deployment/device/release approval.
