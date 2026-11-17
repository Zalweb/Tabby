# HOME-001 — Dashboard labels and monthly filter misrepresent data

```json task-metadata
{
  "id": "HOME-001",
  "area": "home-and-notifications",
  "title": "Dashboard labels and monthly filter misrepresent data",
  "milestone": "M1",
  "priority": "P2",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "b5491d3e33f8401aee33dd04c18296bb141086e5",
  "updated_at": "2026-11-04T06:10:00+08:00",
  "audit_ids": [
    "AUD-20261031-033"
  ],
  "dependencies": [
    "LED-003",
    "PAY-001"
  ],
  "read_set": [
    "AGENTS.md",
    "docs/INDEX.md",
    "docs/project/INSTRUCTIONS.md",
    "docs/project/DECISIONS.md",
    "docs/progress/STATUS.md",
    "docs/plans/home-and-notifications.md",
    "docs/progress/tasks/HOME-001.md",
    "docs/plans/IMPLEMENTATION.md",
    "docs/progress/tasks/INT-001.md",
    "docs/progress/tasks/LED-001.md",
    "docs/progress/tasks/LED-003.md",
    "docs/verification/VER-GRP-001.md",
    "docs/verification/VER-GRP-002.md",
    "docs/verification/VER-GRP-003.md",
    "docs/verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md",
    "integration_test/android_device_matrix_seed_test.dart",
    "integration_test/android_device_matrix_test.dart",
    "test_driver/integration_test.dart"
  ],
  "coverage": [
    "lib/features/home/**",
    "test/**",
    "supabase/**",
    "lib/core/**",
    "pubspec.yaml",
    "pubspec.lock",
    "lib/**",
    "scripts/**",
    "docs/**"
  ],
  "verification": [
    "VER-HOME-001",
    "VER-M1-ACCEPTANCE-REVIEW",
    "VER-QA-001-ANDROID-DEVICE-MATRIX"
  ],
  "required_checks": [
    "regression",
    "android-device"
  ],
  "acceptance_review": {
    "local_review": "passed",
    "at": "2026-11-01T23:41:43.428Z",
    "commit": "14d1cd6d262e9ce39992e8d3258a358ed318d366",
    "scope": "Acceptance inventory and local regression review only; independent/external acceptance is not established",
    "pending_checks": [
      "android-device",
      "integration-review"
    ]
  }
}
```

## Scope and acceptance

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-033). Primary owner role: Mobile agent.

- Problem: Dashboard labels and monthly filter misrepresent data.
- Impact: Outstanding debt is labeled expense and all-time activity appears monthly.
- Implement: Use You are owed/You owe and explicit rolling 24-hour/7-day/calendar-month activity filters.
- Acceptance: Boundary dates filter correctly and KPIs match outstanding obligations rather than spending.
- Starting point: [source](../../../lib/features/home/presentation/home_dashboard_screen.dart).

## Implemented

Current result (2026-10-31T19:35:55.320Z): Dashboard uses You are owed/You owe for outstanding obligations and keeps these totals independent of activity filters. Group payables/receivables follow actual pairs even when group aggregate is zero; viewer identity is explicit in state. Legacy groups lacking member details retain known net totals with a review notice. Activity filters now show Last 24h, Last 7 days and This month with exact inclusive rolling bounds, local calendar month, future exclusion and stable sorting. Existing disputed server rows map to a read-only status and are excluded from local/pair balances to match SQL, without adding dispute-creation controls.

## Remaining and unverified

Emulator result (2026-11-04T06:05:00+08:00): seeded dashboard showed `You are owed` 5,000 centavos and `You owe` 2,300 centavos; This month returned 1 row, Last 7 days 2, and excluded the future row. This used synthetic in-memory data, so actual authenticated account loading and backend refresh remain unverified. See [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-10-31T19:35:55.320Z): Real Android viewport/large-text/timezone and deployed-data journeys remain unverified. Legacy incomplete group shares still require explicit review; no financial history is rewritten. Review found a residual activity-only local/server fuzzy merge in LED-002 that can hide a distinct log; reopening that task next. Reminder derivation/preferences/delivery remain HOME-002 through HOME-004.

## Verification results

API 37 emulator widget-harness assertion passed against synthetic seed data: labels/centavo amounts were correct, calendar month count was 1, rolling seven-day count was 2, and future activity was excluded. See [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-10-31T19:35:55.320Z): [VER-HOME-001](../../verification/VER-HOME-001.md): Dart analysis clean; initial focused dashboard/group/interactive/empty-state suite passed 20/20; final full Flutter suite passed 376/376 including the legacy-group regression and final label refinements. Nine new regressions cover rolling/calendar boundaries, UTC-equivalent instants, future exclusion, same-price IDs, zero-aggregate pair totals, submitted/confirmed payment effects, disputed/cancelled preservation, legacy review and actual dashboard filtering.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Current handoff (2026-11-04T06:05:00+08:00): keep `implemented`. Follow up with authenticated seeded account data and real Android viewport/timezone acceptance; current evidence covers in-memory synthetic rows only.

Current result (2026-10-31T19:35:55.320Z): Correct LED-002 residual activity identity reconciliation and explicit operation mapping, then continue HOME-002 obligation-based reminders and other M1 tasks.

## History

- 2026-11-04T06:05:00+08:00 - API 37 emulator dashboard labels/filters matched synthetic seed (owed 5,000, owing 2,300 centavos; month=1, seven-days=2, future excluded). No live account refresh. See [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

- 2026-11-04T05:36:22+08:00 - Codex root / Windows claims the API 37 emulator device-matrix tranche for SEC-001, SEC-003, HOME-001..004 and QA-001 on `codex/m1-application-fixes`, base `33a89e8c37394f0e7d4983f98d9e1458982015ea`. Read mandatory docs, security/home plans and task handoffs, existing API37 emulator behavior evidence and Flutter integration harness. Reserve only existing integration_test/test_driver harness plus named task handoffs and VER-QA-001-ANDROID-DEVICE-MATRIX evidence; no dependency changes. Emulator only; no signing, release dispatch, M2, live/production change or physical-device claim.


- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-10-31T19:25:41.190Z — Codex root claims truthful outstanding KPI labels and explicit rolling/calendar activity filters with boundary regressions; base acd846d40c50682f4c108d297a7203a624f995a5. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-10-31T19:26:39.043Z — Codex root claims truthful outstanding KPI labels and rolling/calendar activity filters; supersedes pre-documentation-fix base; base b5491d3e33f8401aee33dd04c18296bb141086e5. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-10-31T19:35:55.320Z — Dashboard uses You are owed/You owe for outstanding obligations and keeps these totals independent of activity filters. Group payables/receivables follow actual pairs even when group aggregate is zero; viewer identity is explicit in state. Legacy groups lacking member details retain known net totals with a review notice. Activity filters now show Last 24h, Last 7 days and This month with exact inclusive rolling bounds, local calendar month, future exclusion and stable sorting. Existing disputed server rows map to a read-only status and are excluded from local/pair balances to match SQL, without adding dispute-creation controls.

Remaining: Real Android viewport/large-text/timezone and deployed-data journeys remain unverified. Legacy incomplete group shares still require explicit review; no financial history is rewritten. Review found a residual activity-only local/server fuzzy merge in LED-002 that can hide a distinct log; reopening that task next. Reminder derivation/preferences/delivery remain HOME-002 through HOME-004.

Verification: Dart analysis clean; initial focused dashboard/group/interactive/empty-state suite passed 20/20; final full Flutter suite passed 376/376 including the legacy-group regression and final label refinements. Nine new regressions cover rolling/calendar boundaries, UTC-equivalent instants, future exclusion, same-price IDs, zero-aggregate pair totals, submitted/confirmed payment effects, disputed/cancelled preservation, legacy review and actual dashboard filtering. Code review found the client did not map existing SQL disputed rows; added read-only mapping/exclusion without implementing hidden M2 dispute commands. Existing UI expectations were updated to explicit period/obligation labels. Analyzer const/braces suggestions were corrected before final full verification. Residual activity fuzzy reconciliation is explicitly recorded for the next LED-002 batch rather than treated as solved by the date filters. No live deployment/publication. Next: Correct LED-002 residual activity identity reconciliation and explicit operation mapping, then continue HOME-002 obligation-based reminders and other M1 tasks.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: android-device, integration-review. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).
