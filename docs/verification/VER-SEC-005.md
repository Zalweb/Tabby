# VER-SEC-005 ? Private profile copy and deletion requests

```json verification-metadata
{
  "id": "VER-SEC-005",
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
  "timestamp": "2026-11-01T18:27:13.348Z",
  "tested_commit": "9faaee8445287ce0dc2879758022c07e3cf25674",
  "dirty_tree": true,
  "environment": "Windows; isolated codex/privacy-controls worktree; Flutter/Dart; PostgreSQL/WASM PGlite with synthetic JWT boundary and source core/privacy SQL. No live Supabase or physical device.",
  "commands": [
    "flutter test --no-pub",
    "dart analyze --fatal-infos",
    "node scripts/test-privacy-export.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 9faaee8445287ce0dc2879758022c07e3cf25674"
  ]
}
```

## Expected and actual results

Full Flutter suite passed 576/576, including six new privacy service/widget regressions. Final Dart analysis clean. Export rejects unauthenticated, foreign, malformed and late-session results, prevents parallel work and permits retry after failure. Screen discloses export exclusions, requires deletion confirmation, waits for server acknowledgment and clears displayed data after session change. Source PostgreSQL/WASM checks pass owner profile/contact isolation, explicit field allowlist, anonymous/missing-identity denial, old/malformed/future/anonymous AMR denial, recent-password request acceptance, exact request replay, private request status, direct deletion denial and unchanged acknowledged transaction JSON. AMR claims are injected fixtures, not live GoTrue tokens.

Initial expanded Flutter run failed on lazy-list scrolling in the new widget test and an existing CRLF-sensitive SQL snapshot assertion in a fresh Windows worktree. Fixed the widget scrolling and normalized both sides of the snapshot comparison; full rerun passed. Intermediate analysis flagged two brace-style infos; fixed, final analysis passed.

## Limits and next action

No deployed migration, real JWT/provider, native PostgreSQL, device, signed-candidate or release evidence for these additions. Export intentionally covers only profile and owned contacts, excluding ledger, payment methods, media, notifications, auth records and drafts. Requests are recorded only; reviewed processing/anonymization, full export, status refresh and full Supabase fresh/upgrade acceptance remain. No retention deadline or completed account deletion is claimed. No production mutation.

## Evidence

[Flutter regressions](../../test/features/privacy_export_test.dart), [local PostgreSQL harness](../../scripts/test-privacy-export.cjs), [export SQL](../../supabase/migrations/20261102000001_private_account_export.sql), [request SQL](../../supabase/migrations/20261102000002_account_deletion_requests.sql). Local logs under ignored .dart_tool/privacy-* contain synthetic test output.

- 2026-11-01T18:28:27.594Z ? Privacy source batch committed as 89dc337 on codex/privacy-controls, then copied into the active Tabby workspace only after verifying no concurrent edits to its owned paths. Terminal AND-004 cache/provider/dependency/iOS-workflow changes preserved. Integrated focused privacy suite passed 6/6; main documentation/change-coverage and diff-whitespace checks passed. Full 576-test and analysis evidence applies to isolated privacy branch; no full-suite result is inferred for concurrent terminal changes.
