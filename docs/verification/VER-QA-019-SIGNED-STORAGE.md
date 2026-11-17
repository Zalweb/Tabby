# QA-019 — Release-signed encrypted financial storage upgrade

```json verification-metadata
{
  "id": "VER-QA-019-SIGNED-STORAGE",
  "task_ids": [
    "QA-019"
  ],
  "timestamp": "2026-11-14T14:33:57.367+08:00",
  "tested_commit": "3af8bae7b8578e653491a74c8df902a05cd9a3f1",
  "dirty_tree": true,
  "environment": "Owned API36/16KB x86_64 emulator-5580, production-ID private release AOT artifacts signed by approved new RSA4096 identity",
  "commands": [
    "node scripts/android-signed-storage-test.cjs --device emulator-5580 --baseline-apk <exact private v6 APK> --public-config <ignored public-client-only JSON> --expected-cert 4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a",
    "dart analyze --fatal-infos lib test integration_test",
    "node --test <17 regression files;76 checks>"
  ],
  "checks": [
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "signed-storage-upgrade",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

Actual release/AOT v7 seed and same-production-key v8 upgrade verified the production default encrypted ledger factory, all10000 synthetic history entries/IDs/order/centavos, an unchanged durable operation ID/payload, secure draft and PIN, same secure encryption key and owner isolation. All runtime checks are explicit exceptions rather than release-disabled assertions. A normal-main v9 restoration APK was built and validated before any fixture installation, then installed/launched in finally. Every install rechecked qemu1/x86_64/16384-byte pages, exact APK bytes/certificate, version and unchanged Android appId. Starting v6 APK bytes were pulled and matched the exact known private baseline before replacing it.

Analysis clean and76 Node checks pass, including physical-target and embedded-secret rejection at the new harness boundary. Initial targeted analysis found four const-constructor infos, corrected before builds; final whole Dart analysis clean. No financial app defect reproduced.

## Evidence

[Sanitized artifacts, native proof/log digests and source delta](QA-019-results.json). [Fixture](../../integration_test/android_signed_storage_fixture.dart), [guarded harness](../../scripts/android-signed-storage-test.cjs). Builds are private v1.0.4+7/+8/+9 overrides; pubspec remains unchanged and no public artifact was uploaded.

## Limits and next action

This is a new-key synthetic release-signed storage upgrade rehearsal, not an upgrade from either old debug-signed APK, backend command replay, real financial operation, full app/candidate acceptance or ARM64 runtime. Firebase project choice/quota, provider/live journeys and independent integration review remain open. The personal tablet was never targeted; iOS deferred.

Record post-restoration normal UI observation, review the integration and finish the already tracked provider/exact-candidate gates. No verified/complete or production-ready claim.

2026-11-14T14:35:03.810+08:00 — Observed the restored normal-main release app at Complete your profile with its synthetic account still connected and mobile number empty; no credential or onboarding re-entry. Raw emulator screenshot remains ignored/private. This confirms restoration and Auth gate only, not profile completion or FCM.

2026-11-14T14:35:46.009+08:00 — Final checkpoint validation:76 Node checks pass, full analysis clean, project-memory write/plain/base checks pass at73 tasks/45 findings/95 verification records. Targeted credential/path scan0 findings across15 owned paths; isolated staged archive validates without ignored live config/build artifacts. Diff whitespace passes. Independent integration review remains unverified.
