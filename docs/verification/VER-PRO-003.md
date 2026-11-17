# VER-PRO-003 — Private connections and acknowledged social changes

```json verification-metadata
{
  "id": "VER-PRO-003",
  "task_ids": [
    "PRO-003",
    "PRO-001",
    "SEC-004"
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
      "category": "backend-authorization",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "auth-sdk-isolation",
      "outcome": "unverified"
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
  "timestamp": "2026-11-01T13:05:38.561Z",
  "tested_commit": "c5c319bb8dc10379ef7fc31d1ddfcd08a270adf5",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8; synthetic accounts, real providers/widgets with explicit storage/transport fixtures. Native PostgreSQL17.11 and PGlite selected migration subset through20261101000010; actual authenticated/anon SQL roles, eight independent native sessions. Installed GoTrue2.27.2 source inspected; no actual email, live Supabase HTTP or Android device.",
  "commands": [
    "flutter test test/features/connection_preferences_test.dart test/features/relationship_rules_test.dart",
    "flutter test test/features/connection_preferences_test.dart test/features/interactive_features_test.dart test/features/backend_data_handling_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "node scripts/test-money-commands.cjs",
    "node scripts/test-backend-native.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base c5c319b",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed505/505; Dart analysis clean; Android debug APK built. Sixteen new model/widget regressions plus existing relationship coverage verify private preference restart/account isolation, acknowledgment/error retention, stable retry operation, revision conflict/refresh, newer authoritative snapshots and cache persistence, parallel suppression, local/server cache failure distinctions, corrupt-cache recovery, actor changes, financial preservation, archive/restore and retained failed confirmations. Expanded focused suite passed66/66. Native PostgreSQL17.11 and PGlite pass owner snapshots, accepted-friend-only private labels, replay/conflict/stale revisions, outsider/anonymous and explicit wrong-owner denial, archive/restore without shared-tab mutation, unfriend retaining exact expense/payment rows/roster and a4000-centavo outstanding balance. Eight independent authenticated native sessions replay one social operation once and admit one of eight competing revision-bound changes; existing money/QR/push/phone/profile contracts still pass.

## Evidence

[Connection regressions](../../test/features/connection_preferences_test.dart), [private preferences](../../lib/features/connections/application/connection_preferences.dart), [truthful Connections UI](../../lib/features/connections/presentation/connections_screen.dart), [owner-bound SQL](../../supabase/migrations/20261101000010_connection_preferences.sql), [role and immutable-history acceptance](../../scripts/test-connection-preferences.cjs), [native races](../../scripts/test-backend-native.cjs). Core update_profile_v1 is internal after migration10; clients use update_profile_v2 with expected owner. Old shared archive API rejects writes. No existing financial history, canonical profile or global archive status is rewritten.

## Limits and next action

These are selected SQL/Flutter fixture checks, not full hosted policies, actual email SDK/session safety or device journeys. The known Auth mutation race remains implementation work in SEC-004/PRO-001. Historical shared-archive recovery requires deployed inventory/admin review. App and additive migration10 must be rolled out together; absence of new RPCs fails visibly. No real user data, credentials, deployment or publication.
