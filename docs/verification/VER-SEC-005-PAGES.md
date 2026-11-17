# VER-SEC-005-PAGES

```json verification-metadata
{
  "id": "VER-SEC-005-PAGES",
  "task_ids": [
    "SEC-005"
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
      "category": "local-backend-authorization",
      "outcome": "passed"
    },
    {
      "category": "backend-authorization",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T18:50:46.205Z",
  "tested_commit": "7191d176e643ef8c94401cae5e03718871e32bbd",
  "dirty_tree": true,
  "environment": "Windows; isolated codex/privacy-controls worktree; Flutter/Dart, synthetic widget fixtures and PostgreSQL/WASM with injected JWT subject. No live account mutations or deployment.",
  "commands": [
    "flutter test --no-pub",
    "dart analyze --fatal-infos",
    "node scripts/test-privacy-export.cjs",
    "TABBY_PRIVACY_SCHEMA=snapshot node scripts/test-privacy-export.cjs"
  ]
}
```

## Expected and actual results

Full Flutter suite passed 586/586 after final session guards and status regression; final analysis clean. Thirteen privacy regressions (six previous, seven paging/status additions) exercise malformed/foreign/oversized pages, stable section/cursor, duplicate/nonadvancing IDs, empty final pages, failure/retry on identical cursor, late-session rejection and reopening/status display without a new submission. Actual source PostgreSQL/WASM fixtures export 104 authorized expenses in seven-record pages exactly once, exclude an unrelated tab, enforce page bounds and reject anonymous callers. Separate tabs/shares/payments sections, no-membership empties, owner-only deletion status and original request/history preservation pass. Both migration-core and fresh snapshot-core inventories run the same privacy contract tests.

During source review, schema_all.sql lacked transactions.status despite indexing/using it; the authoritative core migration contains it. Restored the same declaration in the fresh snapshot. The snapshot-core fixture executes real table/index DDL and privacy migrations, not the entire Supabase provisioning script.

Initial new widget tests selected multiple nested Scrollables; scoped to the outer scrollable and reran successfully. Two analyzer brace infos fixed. A speculative test assumed a particular microtask scheduling order; it was invalid for Dart's actual continuation behavior and was replaced with a real deferred status-read/session-replacement regression. The final full run and analysis passed. No device/release claim follows.

## Evidence

[Privacy paging regressions](../../test/features/privacy_ledger_test.dart), [source SQL](../../supabase/migrations/20261102000003_private_ledger_export_pages.sql), [PostgreSQL harness](../../scripts/test-privacy-export.cjs), [client guards](../../lib/features/profile/application/privacy_export.dart), [screen](../../lib/features/profile/presentation/privacy_controls_screen.dart). Ignored .dart_tool/privacy-capability-* logs contain synthetic test output.

## Limits and next action

Pages are current reads, not one frozen export snapshot. Media bytes, private payment methods, notifications, authentication inventory and local drafts remain excluded and are disclosed in the screen. Profile/owned-contact copy remains the separate limited v1 RPC. Full archival export, reviewed anonymization/retention processing and real Supabase JWT/provider/RLS/fresh-upgrade/device tests remain unfinished. This does not mark SEC-005 complete and applies no migration to a live backend.

- 2026-11-01T18:51:59.682Z ? Active-workspace integration: 16/16 privacy/capability tests passed after copying only nonconflicting owned changes. Project-memory/base-coverage and whitespace checks passed; unrelated terminal work remains present.
