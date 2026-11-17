# VER-PRO-001 — Acknowledged profile writes and Auth-owned email

```json verification-metadata
{
  "id": "VER-PRO-001",
  "task_ids": [
    "PRO-001"
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
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "backend-integration",
      "outcome": "unverified"
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
  "timestamp": "2026-11-01T06:03:43.810Z",
  "tested_commit": "5e838f2be4d2eae1b8cf6c97ce25d5e7dae4884e",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8; real provider/widgets with synthetic identities and injected transport/storage. Native PostgreSQL17.11 and PGlite financial migration subset through20261101000008; minimal SQL Auth fixture, authenticated/anon RPC roles. No GoTrue/email delivery, full Supabase services, hosted configuration or device.",
  "commands": [
    "flutter test test/features/profile_persistence_test.dart",
    "flutter test test/features/interactive_features_test.dart test/features/e2e_all_screens_buttons_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "node scripts/test-money-commands.cjs",
    "node scripts/test-backend-native.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 5e838f2",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 476/476; Dart analysis clean; Android debug APK built. Eleven new provider/service/widget regressions cover delayed acknowledgment, canonical authoritative rows, rejection/transport error retention, parallel save exclusion, same-account session changes/disposal, foreign responses, email cooldown/failure/pending verification, and idempotent sheet closure during simultaneous account/session changes. Native PostgreSQL17.11 and PGlite profile-write contracts pass authenticated own-row acknowledgment, unsupported-field/anonymous/missing-profile denial, duplicate-phone rollback, Auth-only email and preservation of edits despite stale metadata/phone reuse. Existing financial/QR/reminder/push/concurrency contracts still pass.

## Evidence

[Provider/UI regressions](../../test/features/profile_persistence_test.dart), [profile form](../../lib/features/profile/presentation/profile_edit_sheet.dart), [verification request service](../../lib/features/profile/application/profile_email_change.dart), [additive RPC/trigger migration](../../supabase/migrations/20261101000008_profile_writes.sql), [SQL acceptance](../../scripts/test-profile-writes.cjs). The SQL Auth fixture simulates a confirmed email-row update only; it does not prove email delivery or confirmation enforcement in a live service.

## Limits and next action

Hosted Auth must enforce email confirmation and double-confirm changes, with real allowlisted callbacks/SMTP. Source config and SDK requests do not prove hosted settings. New API requires the additive migration; absent RPC produces visible failure rather than a false local save. No existing financial history or legacy profile/wallet data is bulk rewritten. No deployment/publication.
