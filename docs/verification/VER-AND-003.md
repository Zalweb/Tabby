# VER-AND-003 — Account-bound picker recovery and durable guarded entry drafts

```json verification-metadata
{
  "id": "VER-AND-003",
  "task_ids": [
    "AND-003"
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
      "category": "android-build",
      "outcome": "passed"
    },
    {
      "category": "web-build",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T14:47:35.835Z",
  "tested_commit": "2aa8b7df0ef0bd6e3f0f11c5f44bc608997e64f0",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8; encrypted-storage mock boundary, actual application forms and synthetic picker/LostDataResponse fixtures. Android debug compilation/JDK and JavaScript web build only. No native picker, emulator/device, live Auth/Storage or actual financial data.",
  "commands": [
    "flutter test test/features/profile_avatar_test.dart test/features/picker_recovery_draft_test.dart test/features/retained_entry_forms_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "flutter build web",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 2aa8b7d",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 570/570; Dart analysis clean; Android debug APK and JavaScript web builds passed after the final photo-ID fix. Twenty-three new permanent regressions cover durable-before-launch context, restart ownership/workflow isolation, lost native result fixtures, cancellation, old acknowledgment/new image, failed writes and retry, invalid image size, explicit discard, stable expense/payment retries, zero-balance cash replay, restored method IDs/revisions, profile rejection, recovered proof/receipt owned bytes without money writes, exact-route session closure, corrupted draft exit and system back through expense steps. Focused avatar/recovery/forms suite passed 36/36 before adding no further executable changes.

## Evidence

[Picker/draft regressions](../../test/features/picker_recovery_draft_test.dart), [real entry form regressions](../../test/features/retained_entry_forms_test.dart), [recovery coordinator](../../lib/core/services/picker_recovery.dart), [account draft storage](../../lib/core/services/form_draft_store.dart), [exact-route guard](../../lib/core/widgets/account_draft_guard.dart), [payment form](../../lib/features/tabs/presentation/payment_draft_form.dart), [expense form](../../lib/features/tabs/presentation/add_expense_modal.dart). Installed image_picker1.2.3 documentation/API was read locally; retrieveLostData is wired at actual startup. Test images/data are synthetic.

## Limits and next action

Widget/SDK-boundary and build evidence only. Android process/activity recreation and live backend checks remain open; no SQL changed, deployed migrations, device evidence, public publication or signed-candidate approval.
