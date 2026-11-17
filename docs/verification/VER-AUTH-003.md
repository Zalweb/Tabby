# VER-AUTH-003 — Durable profile setup and canonical mobile details

```json verification-metadata
{
  "id": "VER-AUTH-003",
  "task_ids": [
    "AUTH-003",
    "AUTH-004",
    "QR-001",
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
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "backend-authorization",
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
  "timestamp": "2026-11-01T05:29:31.732Z",
  "tested_commit": "d57935926e2720300e5758cb91028b92e12570e0",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8; explicit secure-storage/transport mocks and synthetic drafts/identifiers. Actual setup/receiving editor/router widgets run locally. Android debug compilation with Studio JDK. Native PostgreSQL17.11 and PGlite financial migration subset through20261101000007; synthetic auth/Storage fixtures, trigger writes as DB owner and availability RPCs as authenticated/anon. No live Supabase/profile HTTP, real wallet or Android device.",
  "commands": [
    "flutter test test/features/profile_setup_draft_test.dart test/features/complete_profile_multi_payment_test.dart",
    "flutter test test/features/complete_profile_multi_payment_test.dart test/features/profile_setup_draft_test.dart test/features/payment_method_lifecycle_test.dart test/sprint1_api_services_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base d579359",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed451/451; Dart analysis clean. Focused setup/model suite passed14/14 before final full verification. Thirteen new model/provider/widget regressions cover partial success, restart/response-loss stable retries, owned immutable bytes/account isolation, persistence failure, preference rollback/promotion, reentrant writes, deferred resume, corrupt draft retention, disposed/session-changed results, metadata provider lifetime and same-account auth revisions. The existing setup widget regression now asserts no automatic GCash, no account-number QR generator, explicit receiving confirmation and honest failed-save state. Android debug APK builds. Native PostgreSQL17.11 and PostgreSQL/WASM subsets pass phone canonicalization/uniqueness/availability alongside existing financial/QR/push contracts. Eight native owner-role equivalent-format writes admit exactly one canonical phone.

## Evidence

[Setup/model regressions](../../test/features/profile_setup_draft_test.dart), [explicit setup UI](../../test/features/complete_profile_multi_payment_test.dart), [retained draft model](../../lib/features/auth/application/profile_setup_draft.dart), [shared editor](../../lib/features/payment_methods/presentation/payment_methods_sheet.dart), [mobile normalization](../../lib/core/utils/philippine_phone.dart), [SQL contracts](../../scripts/test-profile-phones.cjs), [native races](../../scripts/test-backend-native.cjs). The receiving editor runs real decode validation already covered by QR tests; no generic account QR action remains in application flows. Canonical-phone trigger changes no historical rows on migration application, and no amount/name identity inference is added.

## Limits and next action

No deployed migrations, full profile RLS/HTTP, live wallet, device picker/process death or cross-device draft restoration is proved. Local encrypted draft size is bounded; large-image retention/performance needs AND-004/device checks. No real user financial data/receipt images, credentials, deployment or publication.
