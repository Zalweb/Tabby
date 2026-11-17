# QA-003 — Mobile audit, reproduced repairs and current local acceptance

```json verification-metadata
{
  "id": "VER-QA-003-MOBILE",
  "task_ids": [
    "QA-003",
    "PAY-002",
    "PAY-003",
    "REL-001"
  ],
  "timestamp": "2026-11-13T16:38:08.670+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Codex root on Windows; Flutter3.47.8/Dart3.13.7/Node26.13.0; local encrypted SQLite fixtures, PostgreSQL17.11 and PostgREST16.5 loopback; synthetic/self-issued JWT subjects; PGlite financial subset. No connected Android device, AVD, Xcode or iOS runtime. Azure GET-only probes use the anon client key; no remote data mutations.",
  "commands": [
    "git status --short --branch; git rev-parse HEAD; git diff --binary",
    "flutter test --no-pub --reporter expanded (baseline and post-repair)",
    "flutter analyze --no-pub (baseline and post-repair)",
    "dart analyze lib/core/services/receipt_attachment_service.dart test/features/receipt_upload_transport_test.dart test/ios_notification_configuration_test.dart (final scoped source check)",
    "flutter test --no-pub --reporter expanded test/features/receipt_upload_transport_test.dart test/ios_notification_configuration_test.dart (failure reproduction)",
    "flutter test --no-pub --reporter expanded test/features/receipt_upload_transport_test.dart test/ios_notification_configuration_test.dart test/features/payment_proof_test.dart test/features/receipt_revisions_test.dart test/features/session_scope_test.dart test/features/sync_retry_policy_test.dart",
    "node --test scripts/check-project-memory.test.cjs scripts/android-release.test.cjs scripts/usb-test.test.cjs scripts/azure-full-template.test.cjs scripts/azure-full-seal.test.cjs scripts/azure-full-prepare-export.test.cjs scripts/azure-package.test.mjs backend/app.test.mjs scripts/test-account-deletion-worker.mjs scripts/test-account-deletion-transport.mjs scripts/test-reminder-push-worker.mjs scripts/test-recurring-worker.mjs scripts/test-m2-schema-snapshot.cjs test/release_workflow_test.js",
    "node scripts/test-backend-native.cjs; node scripts/test-money-commands.cjs",
    "node .dart_tool/native-db/qa001-local-api-additional.mjs (reviewed existing loopback-only harness)",
    "flutter build apk --debug --no-pub --dart-define=TABBY_USB_TEST=true",
    "aapt dump badging build/app/outputs/flutter-apk/app-debug.apk",
    "adb devices -l; adb mdns services; emulator -list-avds",
    "node scripts/azure-full-probe.cjs <documented-destination-HTTPS-origin> .dart_tool/azure-full/public-config.json",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs; node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0; git diff --check"
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
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "local-postgrest-fresh-upgrade",
      "outcome": "passed"
    },
    {
      "category": "local-http-acceptance",
      "outcome": "passed"
    },
    {
      "category": "automation-regression",
      "outcome": "passed"
    },
    {
      "category": "ios-notification-configuration",
      "outcome": "passed"
    },
    {
      "category": "android-debug-build",
      "outcome": "passed"
    },
    {
      "category": "platform-denial-probes",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "ios-device",
      "outcome": "unverified"
    },
    {
      "category": "upgrade",
      "outcome": "unverified"
    },
    {
      "category": "oauth",
      "outcome": "unverified"
    },
    {
      "category": "16kb-device",
      "outcome": "unverified"
    },
    {
      "category": "release-artifact",
      "outcome": "unverified"
    },
    {
      "category": "release-authorization",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

The audit tests the dirty integrated source above, not a clean release candidate. Existing QA-002 Android package/configuration and AZ-001 preparation were already present at preflight and were preserved. No web source changes or web builds were performed. The complete shared Flutter suite includes existing shared/web widget regressions; those are compatibility checks, not web improvement work.

| Check | Actual result and scope |
|---|---|
| Baseline | Flutter651/651, Node56/56, analyzer with no issues, native financial/schema-subset contracts and independent-session concurrency passed. The first sandbox attempt could not write the Flutter SDK lockfile; the interrupted approval attempt produced no completed suite. The resumed baseline subsequently finished successfully. |
| Failure reproduction | Two passes and six failures: referenced-object replay returned403; a same-path/different-byte upload overwrote the unreferenced fixture; retries lacked an authorized byte read; unreadable duplicates and changed-account acknowledgment were accepted; iOS native delegate configuration was absent. These are local fixture/static results, not real-device reproduction. |
| Receipt repair | Create-only upload; duplicate conflict triggers authorized byte download and exact comparison. Replays can proceed after the object became immutable. Conflicts, ordinary denial and changed-session responses fail without overwrite or acknowledgment. Empty/over-5-MB retained bytes fail before network use. No grants, object mutation policy, money RPC or confirmation semantics were changed. |
| Targeted acceptance | Initial24/24 and final25/25 across proof/receipt/retry/session/iOS configuration files passed. Initial post-repair fixture run failed because its new download handler assumed an `/authenticated/` prefix; the installed real storage_client uses `/object/<bucket>/<path>`. Corrected only the fixture route; all privacy/conflict assertions remained. The retained-byte-boundary test is included in full regression and the final focused run. |
| Full Flutter regression | 659/659 passed, with the real loopback Storage client, encrypted-ledger tests, queue/session tests and all existing widget tests. No device or remote provider is exercised by this total. |
| Analysis | Final `flutter analyze --no-pub`: no issues (78.9s). Baseline also passed. |
| Node | Final combined61/61 passed, including worker denial/leases, packaging, memory/release verifiers, tablet isolation, Azure preparation, M2 snapshot parity and four corrected mobile workflow checks. |
| Legacy workflow defect | The additional old release_workflow_test.js failed because it demanded automatic `workflow_run` publication. That expectation predates the accepted manual exact-candidate contract. Replaced it with checks for manual main-only/protected publication, run/commit provenance, verifier-before-publication order and private unsigned iOS artifacts. An intermediate JS template syntax error was corrected; final13/13 combined workflow/snapshot/release tests and final61/61 Node checks passed. No workflow was enabled, dispatched or weakened. |
| SQL | Native PostgreSQL17.11 suite passed including eight independent sessions, conflicting operation denial, confirmation overpayment races, receiving-method default uniqueness, reminder/worker leases, correction consent, explicit contact transfers and hidden M2 contracts. PGlite also passed its serial source-contract suite; it does not establish independent-session concurrency. |
| Local fresh/upgrade HTTP | Reviewed existing local harness applied50/50 migrations /965 statements fresh, then32/32 pending migrations /493 statements over its reconstructed18-history baseline, yielding50 history rows. PostgREST16.5 journeys passed, including a committed HTTP response actually dropped by a loopback proxy, retries/conflicts, concurrent confirmations, group parties, malformed values, private methods, proof status,16 follow-up assertions and10 group/privacy assertions. Auth/Storage platform tables and tokens are fixtures; privacy cleanup simulates Admin/Storage actions in SQL. This is not a full Supabase platform installation or live upgrade. |
| Android packaging | Isolated debug build passed (assembleDebug100.7s). Actual APK badging identifies `com.zalweb.tabby.usbtest`,1.0.4+5, debuggable. No production-package install, user data change or signed-release claim. Existing Java native-access and package_info_plus Kotlin-plugin future-compatibility warnings remain. |
| Final packaging/source check | Actual debug APK ZIP and nine ARM64/x86_64 ELF libraries pass static16KB alignment checks. Full659-test/build/full-analysis checkpoints precede a formatting-only and unused-catch-variable cleanup in ReceiptAttachmentService; final25-test focused regression and scoped analysis pass on the final source hashes. This does not establish a clean signed candidate or16KB runtime. |
| Azure GET probes | Six passed at2026-11-13T08:21:01.240Z: TLS/Auth health200; signup disabled; missing key401; keyed nonexistent table404/PGRST205; client OpenAPI403; unauthenticated dashboard401. No rows/accounts/provider settings were changed or read. Restore parity and provider completion were not reassessed by these probes. |
| Runtime availability | ADB device/mDNS inventories and default emulator AVD list were empty. No Xcode, Docker or Podman command was available. Physical Android/iOS, full local Supabase, provider delivery and signed-candidate acceptance remain blocked by their actual environments. |

## Evidence

[Sanitized current local results](QA-003-local-results.json) retain counts, assertion names and source/log digests without private baseline catalogs, credentials or images. [Source manifest](QA-003-source-manifest.json) identifies mobile/backend/build/test inputs in the dirty tree; HEAD alone does not identify this source. [Repair changelog](BUG_FIX_CHANGELOG.md) links affected files and [task](../progress/tasks/QA-003.md) records ownership/read set. Historical Azure restore and tablet results remain in [restore](VER-QA-002-AZURE-RESTORE.md) and [tablet](VER-QA-002-WIFI-TABLET.md) records and are not recast as this run's results.

Ignored raw outputs are under `.dart_tool/readiness/`: `flutter-baseline.log`, `analyze-baseline.log`, `node-baseline.log`, `native-baseline.log`, `reproduction.log`, `repair-targeted.log`, `flutter-final.log`, `analyze-final.log`, `node-final.log`, `pglite-final.log`, `local-http-full.log`, `contracts-workflow.log`, `contracts-workflow-final.log`, `android-build.log` and `azure-readonly-probes.json`. SDK invocations use `C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe C:/src/flutter/bin/cache/flutter_tools.snapshot`; command metadata uses the equivalent Flutter CLI spelling. The local HTTP harness and historical inventory inputs are ignored machine-local fixtures; the durable summary records their hashes and limitations rather than publishing their contents.

Final source/log checkpoints add `repair-targeted-final.log` (25/25) and `scoped-analysis-final.log` (no issues). A narrow literal private-key/service-role-JWT scan found zero matches across454 nonignored source inputs; this is not general secret or advisory clearance. Documentation memory refresh, validation and audit-base coverage passed with57 tasks/45 findings/77 evidence records; `git diff --check` passed. Preservation/final Git inventory is recorded in the local results artifact; no staging/commit/clean-tree claim is made.

## Limits and next action

NO-GO for production Android M1/M3 and iOS distribution. Local repair/regression results are passed; full mobile/Auth/Storage/Realtime/provider acceptance, independent integration review, exact clean release artifact/certificate/digest, physical upgrade, Google OAuth,16KB runtime and release authorization remain unverified. iOS notification configuration has static regression only; iOS remote push and QR save/share are separate unwired capabilities. No remote mutations, migrations, cloud changes, endpoint cutover, signup/scheduler/M2 activation, signing, publication or messages were performed. Follow the [remaining issues](REMAINING_ISSUES.md) and [release contract](../releases/README.md); do not promote QA-001/QA-002/REL-001 or any incomplete M1 task on the strength of these local checks.
