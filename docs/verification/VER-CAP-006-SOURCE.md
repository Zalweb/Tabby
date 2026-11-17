# VER-CAP-006-SOURCE ? Full correction source integration

```json verification-metadata
{
  "id": "VER-CAP-006-SOURCE",
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
  "timestamp": "2026-11-01T19:49:19.092Z",
  "tested_commit": "684004b1b45660d9215b93891e6d37bbf66ffb05",
  "dirty_tree": true,
  "environment": "Windows; Flutter/Dart synthetic account/store/widget fixtures; native PostgreSQL 17.11 and PostgreSQL/WASM source financial migration subsets. No live Supabase, device or deployment.",
  "commands": [
    "flutter test --no-pub",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs (TABBY_NATIVE_DB_MODULE selects existing ignored native tooling)",
    "node scripts/test-money-commands.cjs (existing PGlite tooling)",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 684004b1b45660d9215b93891e6d37bbf66ffb05"
  ]
}
```

## Expected and actual results

Full Flutter 603/603 passes, final analysis clean. Five new tests cover actual parsed bilateral action exposure (fixing the previous empty bilateral participants projection), cache-preserved applied reasons/parent provenance, malformed metadata rejection, one correct upward-revision reminder despite adversarial ID ordering and equal due dates, all group reviewers rather than only the legacy first reviewer, and explicit manual-contact agreement before a write. Existing twelve correction regressions and all prior app tests pass. A new lazy-list test initially needed scrollUntilVisible instead of ensureVisible for an unbuilt row; corrected and passed.

Native/WASM financial source contracts pass. Multi-party groups keep balances unchanged after partial approval; all other registered participants must approve, and one rejection prevents application. Multiple reversal outputs preserve actual payer/debtor identities and exact integer shares. Pending source reminders and queued push jobs are cancelled only on application. Native competing final group approvals apply one revision. Manual contact payer/debtor directions both correct/cancel, require explicit outside-app agreement by their owner, reject wrong owners, and deny the manual path for claimed contacts or fully registered rows. The audit labels manual agreement as an owner attestation, not authenticated contact consent.

Computed revision metadata authorizes against stored transaction participants even for fabricated composite row input; uninvolved group members cannot read the reason. Financial originals remain in balance replay; only superseded/reversal rows are excluded from reminder candidates. Original, reversal and replacement reasons/provenance survive existing cache serialization, including parent links for a replacement later revised.

## Evidence

[Group/contact migration](../../supabase/migrations/20261102000006_group_contact_expense_changes.sql), [computed projection and job retirement](../../supabase/migrations/20261102000005_expense_revision_projection.sql), [SQL acceptance](../../scripts/test-group-contact-changes.cjs), [native races](../../scripts/test-backend-native.cjs), [actual UI/parser/cache/reminder tests](../../test/features/expense_revision_projection_test.dart), [consent decision](../project/DECISIONS.md#dec-009--explicit-consent-for-expense-changes). PostgREST [primary computed-field documentation](https://docs.postgrest.org/en/latest/references/api/computed_fields.html) was read for explicit selection and unnamed-row argument behavior. Direct HTTP/schema-cache behavior remains unverified.

## Limits and next action

Source implementation is implemented, not complete/released. Full Supabase fresh/upgrade and live JWT/SDK/RLS/realtime/HTTP computed projection, Android permission/process-death/reboot/tap and exact signed-artifact acceptance remain unverified. Already delivered or in-flight remote pushes cannot be recalled; local source checks cover pending/leased job retirement. No live migration, remote account mutation or publication.

- 2026-11-01T19:55:20.142Z ? 0ffd6bc source integrated after nonconflicting baseline checks. The full active-workspace Flutter suite passed 609/609 (including the six existing native-cache draft tests) and Dart analysis is clean. No concurrent cache/provider/dependency/iOS-workflow edits were overwritten. adb devices -l reports no connected device; device acceptance remains unverified. This validates current combined source, not a deployed backend or signed release.
