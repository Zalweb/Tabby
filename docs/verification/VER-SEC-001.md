# VER-SEC-001 — Cold lock and session isolation

```json verification-metadata
{
  "id": "VER-SEC-001",
  "task_ids": [
    "SEC-001",
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
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T13:57:53.389Z",
  "tested_commit": "55271512af22ece6538fdfb2f2ce9d5ef05f715a",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; widget/provider tests with explicit secure-storage/authentication/repository fakes; no device/live auth session.",
  "commands": [
    "flutter test",
    "flutter test test/features/cold_lock_test.dart test/features/session_scope_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 55271512af22ece6538fdfb2f2ce9d5ef05f715a",
    "git diff --check"
  ]
}
```

## Expected and actual results

294/294 full Flutter tests passed; analysis clean. Six new regressions cover held settings readiness hiding sensitive content, storage failure staying closed, cold PIN/wrong PIN/cancel/correct PIN/resume above the router, delayed payment-method results after A-to-B and A-to-A relogin, and current-generation eligibility. The first PIN widget regression exposed a missing overlay for text selection; the lock now owns a navigator and the regression passes.

## Evidence

Permanent regressions: [cold lock](../../test/features/cold_lock_test.dart), [session scope](../../test/features/session_scope_test.dart). The final focused rerun passed 6/6 after adding early stale-load rejection and preserving visible state during token refresh. Full suite passed 294/294 before those guard refinements. Analysis passed with the final guards. Repository memory validation and change coverage passed after adding this evidence section.

## Limits and next action

Global test setup explicitly mocks secure storage; widget authentication and repository responses are controlled boundaries. These do not establish Android keystore, biometric, Supabase auth event ordering, realtime or live backend acceptance. Test those environments before verified/complete. No backend deployment, account mutation or release performed.
