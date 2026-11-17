# HOME-002 — Settled reminders return after refresh

```json task-metadata
{
  "id": "HOME-002",
  "area": "home-and-notifications",
  "title": "Settled reminders return after refresh",
  "milestone": "M1",
  "priority": "P1",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "e16430db144f3bbdc54feaffdb694535f64e78a9",
  "updated_at": "2026-11-04T06:10:00+08:00",
  "audit_ids": [
    "AUD-20261031-034"
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
    "docs/progress/tasks/HOME-002.md",
    "docs/plans/IMPLEMENTATION.md",
    "docs/progress/tasks/INT-001.md",
    "docs/progress/tasks/LED-001.md",
    "docs/progress/tasks/LED-003.md",
    "docs/verification/VER-GRP-001.md",
    "docs/verification/VER-GRP-002.md",
    "docs/verification/VER-GRP-003.md",
    "docs/verification/VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP.md",
    "docs/verification/VER-QA-001-LOCAL-HTTP-M1-GUARDS.md",
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
    "VER-HOME-002",
    "VER-M1-ACCEPTANCE-REVIEW",
    "VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP",
    "VER-QA-001-LOCAL-HTTP-M1-GUARDS",
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

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-034). Primary owner role: Mobile agent.

- Problem: Settled reminders return after refresh.
- Impact: Users can be reminded about obligations already paid.
- Implement: Derive reminders from unresolved obligations; cancel old alarms on confirmation/cancellation.
- Acceptance: Settle dated debt, refresh/restart/reconnect: no reminder or overdue alert returns.
- Starting point: [source](../../../lib/features/tabs/application/tabby_providers.dart).

## Implemented

Current result (2026-11-01T03:59:51.430Z): Due reminders are derived from remaining obligations on cache restoration, server refresh, expense/payment changes, confirmation and explicit identity remapping. Settled pairs never recreate a reminder from the original expense due date or stale reminder cache. Partial balances cover oldest due bills first as a documented presentation policy. Groups retain actual member pairs, including zero aggregate balances, and settling one pair preserves unrelated reminders. Reminder records carry typed counterparty/source IDs; notification IDs use stable digest values. Alarm changes serialize and failures do not undo acknowledged money. Group messages no longer call a zero aggregate fully settled while member obligations remain.

## Remaining and unverified

Emulator result (2026-11-04T06:05:00+08:00): with POST_NOTIFICATIONS granted, the scheduled alarm existed before local `refreshDueReminders()`; after the seeded settled-pair refresh there were 0 reminder rows and no pending alarm. This covered synthetic local state, not authenticated server refresh. See [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-11-01T03:59:51.430Z): Android actual alarm cancellation, reboot, process death, account-switch races and delivery remain unverified. Account-scoped preference/permission enforcement, collision-safe alarm registry and rescheduling reconciliation remain HOME-003/AND-004 work. Closed-app remote delivery and truthful send acknowledgment remain HOME-004. Unknown historical allocations require explicit review; no per-bill payment linkage is invented.

Superseding local HTTP result (2026-11-04): the previous stale scheduled-row failure is fixed. When payment confirmation reduces the payer/recipient balance to zero, the server marks that pair's scheduled reminder `cancelled`, retaining its row for history; refreshed reminder GET returns that cancelled row. Android alarm cancellation, reboot/process-death delivery and live Supabase acceptance remain unverified.

## Verification results

API 37 emulator assertion passed with real Android notification scheduling: pending alarm true before refresh, reminder rows 0 afterward, and pending alarm false. This does not prove live refresh or reboot. Evidence: [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-11-01T03:59:51.430Z): [VER-HOME-002](../../verification/VER-HOME-002.md): Final full Flutter suite passed 394/394; Dart analysis clean. Initial focused reminder/decision/group/empty-state suite passed 19/19, followed by final confirmation and zero-aggregate partial-receipt regressions in full suite. Eleven new tests cover settled/partial/undated/disputed/cancelled obligations, group pair isolation, typed contact/user identity, stable IDs, actual provider cash settlement and stale-cache restart, alarm failure isolation, recipient confirmation and zero aggregate with remaining pairs.

[VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP](../../verification/VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP.md): payment settled and refreshed balance returned zero, but reminder GET returned HTTP 200 and one `scheduled` row for that transaction. Full Flutter suite passed 650/650 and analysis was clean; client-derived view and native delivery are distinct checks.

[VER-QA-001-LOCAL-HTTP-M1-GUARDS](../../verification/VER-QA-001-LOCAL-HTTP-M1-GUARDS.md): payment/confirmation HTTP 200; balance zero; reminder GET HTTP 200 with one retained row at `status=cancelled`. The prior API failure is fixed. Flutter analysis and 650/650 tests pass; loopback/self-issued JWT only, no device acceptance.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Current handoff (2026-11-04T06:05:00+08:00): keep `implemented`; retain this local emulator cancellation result and add authenticated server refresh plus physical Android alarm/restart acceptance before verification. Do not infer HOME-004 delivery from this result.

Current result (2026-11-01T03:59:51.430Z): Continue HOME-003 permission opt-in, account/category preferences, logout cancellation and notification lifecycle tests, then HOME-004 delivery/acknowledgment. Run real settle/refresh/restart/reconnect and reboot/device checks before closure.

Current handoff (2026-11-04T04:15:13+08:00): the settlement trigger in additive migration `20261104000001_m1_cancellation_reminder_guards.sql` cancels only scheduled reminders for the settled payer/recipient pair and retains reminder history. The local HTTP regression now passes. Keep status `implemented` until live backend integration and Android alarm/restart/device checks pass. See [VER-QA-001-LOCAL-HTTP-M1-GUARDS](../../verification/VER-QA-001-LOCAL-HTTP-M1-GUARDS.md).

- 2026-11-04T03:56:19+08:00 - Local HTTP M1 follow-up: Follow-up local HTTP settlement reached zero balance (submission/confirmation HTTP 200; confirmed payment row), but the refreshed reminders endpoint still returned the synthetic reminder with status `scheduled`. This is a persisted reminder lifecycle gap even though the client-derived refresh regression is in the passing Flutter suite. Fix/cancel or suppress stale scheduled rows and rerun; device delivery remains open. Evidence: [VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP](../../verification/VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP.md).

## History

- 2026-11-04T06:05:00+08:00 - API 37 emulator local settled-reminder refresh canceled the existing alarm without deleting history (0 derived due rows; alarm no longer pending). No live server refresh. See [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

- 2026-11-04T05:36:22+08:00 - Codex root / Windows claims the API 37 emulator device-matrix tranche for SEC-001, SEC-003, HOME-001..004 and QA-001 on `codex/m1-application-fixes`, base `33a89e8c37394f0e7d4983f98d9e1458982015ea`. Read mandatory docs, security/home plans and task handoffs, existing API37 emulator behavior evidence and Flutter integration harness. Reserve only existing integration_test/test_driver harness plus named task handoffs and VER-QA-001-ANDROID-DEVICE-MATRIX evidence; no dependency changes. Emulator only; no signing, release dispatch, M2, live/production change or physical-device claim.


- 2026-11-04T04:15:13+08:00 - Codex root claims HOME-002 reminder lifecycle API fix and regression evidence on `codex/m1-application-fixes`, base `da5aa3f79b7fe8a9b8dccd5642686bfca1ca2ff9`. Read mandatory docs, HOME-002/QA-001/dependencies, home plan, prior local HTTP evidence and current payment/reminder SQL. Reserved the additive settlement trigger, snapshot sync, local API regression, plan clarification and task/evidence updates. No competing claim found; starting tree clean. No device or production work.

- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-10-31T19:45:58.758Z — Codex root claims derive due reminders from remaining direct obligations, prune cached settled reminders and reconcile alarms after financial changes; base e16430db144f3bbdc54feaffdb694535f64e78a9. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-11-01T03:59:51.430Z — Due reminders are derived from remaining obligations on cache restoration, server refresh, expense/payment changes, confirmation and explicit identity remapping. Settled pairs never recreate a reminder from the original expense due date or stale reminder cache. Partial balances cover oldest due bills first as a documented presentation policy. Groups retain actual member pairs, including zero aggregate balances, and settling one pair preserves unrelated reminders. Reminder records carry typed counterparty/source IDs; notification IDs use stable digest values. Alarm changes serialize and failures do not undo acknowledged money. Group messages no longer call a zero aggregate fully settled while member obligations remain.

Remaining: Android actual alarm cancellation, reboot, process death, account-switch races and delivery remain unverified. Account-scoped preference/permission enforcement, collision-safe alarm registry and rescheduling reconciliation remain HOME-003/AND-004 work. Closed-app remote delivery and truthful send acknowledgment remain HOME-004. Unknown historical allocations require explicit review; no per-bill payment linkage is invented.

Verification: Final full Flutter suite passed 394/394; Dart analysis clean. Initial focused reminder/decision/group/empty-state suite passed 19/19, followed by final confirmation and zero-aggregate partial-receipt regressions in full suite. Eleven new tests cover settled/partial/undated/disputed/cancelled obligations, group pair isolation, typed contact/user identity, stable IDs, actual provider cash settlement and stale-cache restart, alarm failure isolation, recipient confirmation and zero aggregate with remaining pairs. Implementation review found PartyRef lacked value equality; added typed immutable ID equality/hash so contact/user namespaces remain distinct. Analyzer caught a formatted-anchor omission in the initial decision update and braces/const suggestions; corrected before focused/final runs. Alarm scheduling already had a refresh caller, as corrected in VER-AND-001; this change replaces its unconditional due-date merge with obligation derivation. No device behavior is inferred from scheduler test callbacks. No live deployment/publication. Next: Continue HOME-003 permission opt-in, account/category preferences, logout cancellation and notification lifecycle tests, then HOME-004 delivery/acknowledgment. Run real settle/refresh/restart/reconnect and reboot/device checks before closure.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: android-device, integration-review. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).
