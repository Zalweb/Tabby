# QA-021 — Clean signed tablet live-testing installation

```json verification-metadata
{
  "id": "VER-QA-021-CLEAN-TABLET",
  "task_ids": [
    "QA-021"
  ],
  "timestamp": "2026-11-14T16:06:03.377+08:00",
  "tested_commit": "20034402a43d1e982c24af44c3b05b3395eb34d9",
  "dirty_tree": false,
  "environment": "Exact private v1.0.4+10 normal release APK; physical Lenovo TB321FU/API36/ARM64/4KB and owned API36/x86_64/16KB emulator; separate debug synthetic Auth/Realtime fixtures on Azure migration destination",
  "commands": [
    "flutter build apk --release --build-number=10 --target=lib/main.dart --dart-define-from-file=<ignored public-only Azure client config>",
    "node scripts/verify-android-artifact.cjs --apk <retained exact release APK> --expected-cert <approved production certificate> --commit 20034402a43d1e982c24af44c3b05b3395eb34d9",
    "private ZIP literal/path scan against selected fixture credentials and seed markers",
    "node scripts/usb-test.cjs --suite smoke --transport wifi --device <verified paired tablet>",
    "node scripts/usb-test.cjs --suite live --transport wifi --device <verified paired tablet> --live-config .env.usb-live.json",
    "guarded primary-user test-copy uninstall and fresh verified normal APK installation",
    "pull installed base APK and compare exact SHA256",
    "dart analyze --fatal-infos lib test integration_test",
    "node --test <17 exact file arguments in QA-021-results.json>"
  ],
  "checks": [
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "16kb-device",
      "outcome": "passed"
    },
    {
      "category": "clean-install",
      "outcome": "passed"
    },
    {
      "category": "live-backend",
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

Built the normal lib/main.dart release from clean commit 20034402a43d1e982c24af44c3b05b3395eb34d9 as v1.0.4+10. APK SHA256 9b5ccd7554c90c9248ef65dcc2e50e16722e075609746be9a2e285c31f540751; approved new production certificate 4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a. Actual Flutter process exit0 and clean before/after tree recorded. Nondebuggable manifest, signature, ZIP16KB and ARM64/x86_64 ELF LOAD/RELRO checks pass. ZIP contents contain no packaged ledger database/private signing/config paths, selected fixture credentials or known synthetic seed markers; only public Azure URL/anon identifiers were defined. Normal source initial tabs/activities/reminders are empty. The identical APK fresh-started on16KB emulator and physical ARM64 tablet. Both were visually observed at first onboarding, signed out. The final tablet-installed base APK was pulled and its digest exactly matched the accepted bytes.

Physical temporary .usbtest smoke acceptance passed five named cases including seed, process-restart encrypted draft/owner isolation, stored PIN/right-wrong verification, Android notification permission/preferences and touch/render. Separate real Auth/RLS/Realtime fixture passed, including replication readiness, saved RPC acknowledgment/readback, delivered update and verified original profile restoration. Four read-only anonymous health/RLS probes passed with no exposed profile/transaction/payment-proof IDs. Those fixtures used a separate debug APK, not a login or financial operation in the signed user app. The temporary test app and its local fixture data were uninstalled before installing the normal app fresh.76 Node checks and full Dart analysis pass.

First PowerShell invocation returned1 despite Flutter reporting Built; retained as wrapper failure. Direct actual-process rerun returned0 and supplied the accepted artifact. Existing Java native-access, package_info_plus KGP-future and Cupertino font warnings remain recorded. No missing glyph observed on first onboarding; no general font or dependency clearance inferred.

## Evidence

[Sanitized artifact, installed-byte, source and test results](QA-021-results.json). Build source is the clean claim commit2003440; subsequent updates are documentation only. All483 source hashes match the prior signed-storage record. No source repair was required in this batch. Raw APKs/screenshots and credential-bearing temporary test artifacts remain ignored/local.

## Limits and next action

User chose their existing account and will sign in manually; no agent credentials entered or sample records added to that account. Existing cloud history can load after sign-in. Signup remains disabled; Google/native sign-in and real FCM configuration/delivery are unfinished. This is live acceptance against the Azure migration destination, with final delta synchronization/global cutover and independent review still open. No public publication, backend policy/provider/signup/scheduler change, source-default URL change or financial history deletion occurred. Exact APK cold start does not establish every financial/Storage/provider journey. iOS runtime deferred.

User proceeds through onboarding and uses existing email/password for manual live acceptance. Keep cloud history intact and record reported issues; finish Google/Firebase/provider/cutover and independent review before production signoff. Task implemented, not complete.

2026-11-14T16:07:21.292+08:00 — Checkpoint hygiene: project-memory write/plain/base checks pass at75 tasks/45 findings/97 verification records; targeted credential/path scan0 findings across9 owned documentation paths, isolated staged archive validates with ignored live config/build absent, and diff whitespace passes. Historical MockTabbyRepository class comment still says seeded; current getInitialTabs/getInitialActivities/getInitialReminders return empty lists, as checked directly. No source/comment rewrite required for this installation.
