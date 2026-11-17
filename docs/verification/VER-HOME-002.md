# VER-HOME-002 — Obligation-based due reminders

```json verification-metadata
{
  "id": "VER-HOME-002",
  "task_ids": [
    "HOME-002"
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
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T03:59:51.430Z",
  "tested_commit": "e16430db144f3bbdc54feaffdb694535f64e78a9",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8; synthetic integer-centavo ledger/cache fixtures, explicit secure-storage mocks and injected alarm port. Real provider refresh/restart logic runs with offline repository fixtures; no physical Android or live backend.",
  "commands": [
    "dart analyze --fatal-infos",
    "flutter test test/features/due_reminders_test.dart test/features/payment_decisions_test.dart test/features/group_settlement_test.dart test/features/empty_state_flow_test.dart",
    "flutter test",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 394/394; Dart analysis clean. Initial focused reminder/decision/group/empty-state suite passed 19/19, followed by final confirmation and zero-aggregate partial-receipt regressions in full suite. Eleven new tests cover settled/partial/undated/disputed/cancelled obligations, group pair isolation, typed contact/user identity, stable IDs, actual provider cash settlement and stale-cache restart, alarm failure isolation, recipient confirmation and zero aggregate with remaining pairs.

## Evidence

[Due regressions](../../test/features/due_reminders_test.dart) retain original financial entries, settle/confirm, inject a stale reminder cache and reload through the provider. [Derivation](../../lib/features/tabs/domain/due_reminders.dart) caps dated reminders to remaining pair balances and never treats groups as people. [Stable ID helper](../../lib/core/services/reminder_notification_id.dart) avoids runtime hash instability; collision-safe assignment remains the next task. Existing financial SQL is unchanged.

## Limits and next action

Mock alarm ports do not prove Android delivery/cancellation or process-death durability. Preference enforcement and remote background delivery remain explicit next tasks; source changes are not deployed or release-approved.
