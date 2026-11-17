# QA-018 — Free Firebase and keyless Android background delivery

```json verification-metadata
{
  "id": "VER-QA-018-KEYLESS",
  "task_ids": ["QA-018", "HOME-004", "QA-001", "REL-001"],
  "timestamp": "2026-11-17T07:40:08.046Z",
  "tested_commit": "f8b731463e2dd0efd5f160f82f093fa0c26da1e4",
  "dirty_tree": true,
  "environment": "Windows / Firebase CLI15.36.0 / Azure approved migration functions / actual Lenovo TB321FU API36 ARM64 4KB USB / isolated com.zalweb.tabby.usbtest debug APK",
  "commands": [
    "Firebase official CLI projects:addfirebase for explicitly selected unused project; register main/test apps and SHA1/SHA256",
    "Authenticated billing/API/IAM inventory and FCM-only sender/exact-VM workload federation setup",
    "Live Azure metadata, Google STS, service-account impersonation and synthetic-token FCM validation",
    "node --test scripts/test-reminder-push-worker.mjs (12); neighboring release/sealing/packaging suites (32)",
    "python deploy/azure-full/test_firebase_configuration.py (3); existing callback guards (5)",
    "deno check supabase/functions/reminder-push/index.ts",
    "dart analyze --fatal-infos integration_test/android_fcm_fixture.dart",
    "flutter build apk --debug --target integration_test/android_fcm_fixture.dart --dart-define=TABBY_USB_TEST=true --dart-define-from-file <ignored isolated public Firebase configuration>",
    "Reviewed configure-firebase.py applied through Azure RunCommand; exact prior source hashes; encrypted backup/recovery integrity; functions-only recreate and same-image runtime authorization probe",
    "Hardware/user/package-guarded isolated install, real FCM token, sealed data-only message, background and own NotificationManager inspection"
  ],
  "checks": [
    {"category": "provider-configuration", "outcome": "passed"},
    {"category": "worker-regression", "outcome": "passed"},
    {"category": "firebase-background-delivery", "outcome": "passed"},
    {"category": "android-push", "outcome": "unverified"},
    {"category": "integration-review", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

User explicitly selected the previously reviewed unused project `project-16899afb-9d76-433c-9a2`. Firebase added; billing remains disabled and unattached. Registered production and isolated Android packages with their respective approved release/debug SHA1 and SHA256 certificates. Four public identifiers are prepared separately for each package; no service credential enters the APK.

Google rejected service-account key creation. No key was created and no restriction was weakened. Instead, the existing Azure system-assigned VM identity is trusted through a Google workload identity pool, constrained to its exact tenant, object and VM-resource claims. Only that principal may impersonate the dedicated sender, which has the FCM API role only. The live metadata → STS → impersonation probe passed, and FCM rejected the deliberately synthetic token with400 INVALID_ARGUMENT, establishing sender authorization without a real message. No tokens or subject claims containing private account data are logged.

The worker retains legacy service-account support and adds strictly checked Azure external-account support. Metadata/STS/impersonation destinations, token types, scopes, expiry, redirects and request deadlines are validated. Authorization failure occurs before queue claims. Six new tests were added; the original branch produced3 failures and9 passes across the12-case suite. All12 now pass along with32 neighboring Node checks,3 operator guards,5 existing callback guards, Deno entry checking and scoped fixture analysis. The invalid-Google-response case additionally requires reaching its expected exchange, preventing an unrelated early rejection from satisfying that assertion.

Actual Firebase-configured Android build failed because AGP9 disables resValues by default. Enabling only that build feature corrects the existing public Firebase resource path. The configured debug APK builds in a separate ignored source archive and installs only as .usbtest. A real FCM token was obtained. The Azure federated sender accepted the sealed data-only message; the production native PushService actually posted a `tabby_background_reminders` notification while the app was backgrounded, with exactly the generic title/body. This is actual provider/device delivery, distinct from local alarms or scheduled requests.

Reviewed functions-only deployment `firebase-20261117T073658Z-1dedb1` passed. Exact prior worker hashes matched the committed baseline; encrypted backup decrypted/integrity-checked before mutation. Only the two push files and two functions environment fields changed. The exact deployed worker authenticated inside an ephemeral loopback-only container using the existing Supabase edge-runtime image. It returned a boolean only; no queue claim or notification dispatch in the probe. The container was removed. Auth configuration, existing financial data and scheduler state were preserved. The regular worker scheduler stays disabled pending complete acceptance.

## Evidence

[Sanitized provider/deployment/source/device checkpoint](QA-018-keyless-results.json), [implementation plan](../plans/firebase-keyless-android.md), [configuration operator](../../deploy/azure-full/configure-firebase.py), [worker regressions](../../scripts/test-reminder-push-worker.mjs) and [isolated device fixture](../../integration_test/android_fcm_fixture.dart).

The first delivery inspection incorrectly force-stopped the test package, clearing notifications. That measurement is retained as unproven, not a product failure or pass. Corrected fixture inspects on resume without stopping the process. Initial archive build failed custom-resource configuration; corrected build is recorded. Separate QA-022 checkout disappeared externally after its source commit; no files were restored over other work. QA-018 uses its own ignored git archive and does not occupy the root Android build output. Remote preflight found edge-runtime rather than standalone Deno, so the operator uses the actual runtime image for its validation.

References: [FCM Android setup](https://firebase.google.com/docs/cloud-messaging/android/get-started), [Firebase no-cost plan](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans), [Azure workload federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-other-clouds), [FCM sender IAM role](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging).

## Limits and next action

Task remains in_progress. Final duplicate/closed-process/stale-scope/permission checks are being recorded separately. Real backend registration → reminder acceptance → leased queue → sender → notification/tap, token rotation, account switching/offline logout, force-stop/reboot/locked cold tap and independent review remain incomplete. Direct FCM native scope fixtures do not establish that full backend journey. No owner account or financial test data was used.

Normal main12 is preserved and still lacks Firebase identifiers; subsequent higher same-key normal update must use the prepared public main configuration after concurrent QA-025 verification. Shared source changes and partial fixture acceptance are not final clean-candidate or production approval. No billing, public release, global endpoint cutover or automatic queue scheduler activation.

2026-11-17T07:49:51.102Z — Superseding native completion: background and verified stopped-process fresh message posted. Same-event retry created no extra event notification; a different binding created none; clear scope removed prior alerts and suppressed a new valid-scope event. Fresh permission-denied event produced no alert; permission restored, scope cleared and isolated package removed. Group-summary notifications are excluded from event counts. First am-kill was asynchronous; final repeat explicitly confirmed process absence before invoking sender, and no force-stop claim is made. Real backend registration/reminder/queue, tap/rotation/reboot/full account lifecycle and independent review remain open. Main preserved; normal higher-version update is coordinated by QA-025.

2026-11-17T07:51:50.737Z — Superseding normal-app update: concurrent QA-025 installed same-key normal1.0.4+13 in place. QA-018 independently pulled bytes, verified exact digesta7e260f3674572cbc51adc4a31e105d52919b77012df3590a90208f9f291adb9/certificate/nondebug/ZIP/ELF checks and confirmed all four approved Firebase public values are in actual installed resources. Main firstInstallTime preserved, no owner logout/data clear/private screenshot; test .usbtest absent. Thus earlier main12/no-public-config statements are historical. Actual backend registration/reminder queue, further lifecycle/tap and independent release gates remain open.

2026-11-17T07:54:32.444Z — Final QA-018 handoff validation:32 neighboring Node checks,12 worker checks,3 Firebase/5 existing callback guards, Deno entry and scoped fixture analysis pass. Actual configured test build/native FCM and normal13 artifact/resource evidence recorded. Owned17-file snapshot excludes concurrent entrytest/Google UI/art/reference/skill changes and passes memory refresh/plain/base76 tasks/45 findings/99 records, whitespace and known Google-secret/device-token/account/private-path scan0 findings. Applied worker/operator hashes equal current source. Root full memory passes79/45/102; root base coverage still flags unowned skills/reference files. No coverage broadened, private logs/APKs/configs remain ignored. Current task stays in_progress for queue/full lifecycle/review.

2026-11-17T08:22:00.128Z — Additional real recipient checkpoint: user manually completed spare Google sign-in/notification opt-in in a fresh isolated normal application. Its actual registered native account/binding matches a live Google identity/Auth session and backend push registration, independently checked without reading Auth credentials or logging IDs/tokens. Current public API key is already restricted for Android/required Firebase APIs. Tagged synthetic sender request prepared; awaiting explicit recipient acceptance before any test expense/reminder. [Live checkpoint and operator limits](QA-018-live-reminder-results.json). The sender adapter is authenticated-role SQL fixture context; real sender OAuth/UI is not claimed. The normal test app remains intentionally installed for this next phase.


2026-11-17T10:29:05.386Z — Superseding actual native outcome: warm and killed-process/cold drawer taps now show the correct existing test group/PHP1.00 after explicit link ownership and Dart-listener handshake repair. Signed normal16 delivered in place with preserved data/session; final live financial integrity passes. Prior pending/failed/native14/15 statements are historical. [Current native evidence](VER-QA-027-NATIVE-INTENTS.md) and [results](QA-027-native-results.json). Other lifecycle/review/production gates remain open.
