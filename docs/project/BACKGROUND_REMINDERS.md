# Android background reminders

This source contract belongs to [HOME-004](../progress/tasks/HOME-004.md). It is not deployment or delivery evidence.

## Acceptance and delivery

`send_tab_reminder_v1` atomically persists the recipient inbox row, audit and private delivery jobs. A successful response means accepted, never delivered or read. Jobs target account/session bindings registered before acceptance. New registrations do not resend historical inbox rows.

Tokens and jobs are unreadable to app roles. Authenticated registration associates an installation with the caller only; logout revokes that exact binding. Account switches serialize registrations. Native display is disabled before registration/revocation awaits, and activates only after acknowledgment. Failed remote logout revocation remains available for retry; the native binding stays cleared and server registrations expire after one day without foreground renewal. An in-flight old message is discarded by the native binding check. Firebase token changes while Flutter is alive trigger renewal; changes while closed are reconciled on next foreground/resume.

The worker claims ten jobs at a time with independent two-minute leases, sends requests concurrently with bounded HTTP deadlines, and records provider acceptance. Missing responses retry with exponential backoff and a six-attempt limit; expired worker leases are recoverable. A stale lease cannot finish another attempt. Invalid tokens are retired. Claiming rechecks current binding, opt-in, expiry, active membership and the actual outstanding pair obligation. A payment after claim can race an already transmitted message; alerts contain generic text and always open the current ledger. Duplicate FCM responses replace the same tagged notification and use a bounded recent-event cache.

Only data messages are sent: account/binding/event/tab identifiers, version and kind. They contain no names, balances, receipts or auth tokens. Android checks the binding and OS permission before displaying generic private lock-screen text; foreground realtime handles alerts while the app is open. Cold/warm taps wait for authentication, validate immutable IDs and re-read active tab/group membership before navigation. PIN/biometric and router gates continue to protect the destination.

## Configuration and rollout

1. Apply migrations through `20261101000006_background_reminders.sql` to a disposable full Supabase installation; verify fresh/upgrade policies and functions as real authenticated users before staging.
2. Supply the public Firebase Android app identifiers via build configuration: `FIREBASE_APP_ID`, `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID` as Flutter dart-defines. Gradle emits the corresponding Firebase resources only when all four are present. No synthetic/default project is bundled. No configured identifiers means background alerts remain unavailable; local alarms/inbox still work. Firebase auto-init and analytics collection default off; explicit permitted opt-in requests a token.
3. Deploy `supabase/functions/reminder-push` with its default Supabase gateway JWT check enabled. Store `FIREBASE_SERVICE_ACCOUNT_JSON`, `FIREBASE_PROJECT_ID` and a random `PUSH_WORKER_SECRET` of at least 32 characters in backend secret configuration; the Supabase URL/service-role key remain backend-only. Do not put service-account credentials in the APK or Git.
4. Configure an authenticated server scheduler to POST to the worker periodically, including the gateway authorization and `x-push-worker-secret`. Keep keys in the scheduler's secret store. No cron, project, secret, deployed function or device association is provisioned by this source change. Inspect aggregate worker outcomes and private queue status without logging tokens or credentials.
5. Test actual Android permission allow/deny, channel disable, foreground/background/closed app, force-stop behavior, reboot, cold tap while locked, rejected/settled targets, token rotation, account switching and offline logout. Verify provider acceptance separately from delivery. Android force-stop/OS restrictions and unavailable Google Play services can prevent delivery; inbox history remains available.

Remote iOS/web delivery is not wired by this Android task. Existing local supported-platform behavior remains; candidate/device checks and release gates stay open.

## Primary implementation references

- [Firebase Android receiving](https://firebase.google.com/docs/cloud-messaging/android/receive-messages): data-message callbacks and background behavior.
- [Firebase HTTP v1 authorization](https://firebase.google.com/docs/cloud-messaging/send/v1-api): backend OAuth credentials and sending.
- [Firebase Messaging source release notes](https://github.com/firebase/firebase-android-sdk/blob/main/firebase-messaging/CHANGELOG.md): the pinned Android SDK is 25.1.3; newer API adoption requires separate candidate verification.

Local synthetic regressions do not prove service configuration, Firebase acceptance or physical delivery. See the task's verification records for actual results.

## 2026-11-14T14:20:41.074+08:00 — Provider setup status

User authorized a free Spark Firebase setup without billing. Standard Firebase CLI Google sign-in succeeded; a new Tabby project was denied by account project quota. No unused existing project is yet designated, app registered, sender credential deployed or scheduler enabled. Keep remote availability false until all four public build identifiers and private sender configuration are actually supplied and tested. Local native closed/reboot alarm acceptance does not prove FCM. [Setup evidence and next action](../verification/VER-QA-018-FIREBASE.md).

## 2026-11-17T07:49:51.102Z — Approved Firebase/keyless deployment and actual device delivery

Approved existing project now Firebase-enabled with billing disabled/unattached. Both Android package/certificate sets registered. Google disallows sender key creation; no policy change/key occurred. Existing Azure VM identity federates through an exact tenant/object/VM-resource condition to an FCM-only sender. The worker accepts the validated public external-account configuration in FIREBASE_WORKLOAD_IDENTITY_JSON, keeping legacy service-account support; no sender secret in APK. Functions-only deploy and same-image runtime authorization pass. Actual isolated tablet background/stopped-process delivery, duplicate/no-stale-scope/clear/permission checks pass. [Current evidence](../verification/VER-QA-018-KEYLESS.md).

Remote queue scheduler remains disabled pending full registration/reminder/queue/tap and lifecycle acceptance. Normal main12 still awaits a higher-version public-identifier update by concurrent QA-025; no production-ready claim. Earlier no-designated-project/no-delivery paragraphs are historical, superseded only to this recorded scope.

2026-11-17T07:51:50.737Z — Superseding normal-app update: concurrent QA-025 installed same-key normal1.0.4+13 in place. QA-018 independently pulled bytes, verified exact digesta7e260f3674572cbc51adc4a31e105d52919b77012df3590a90208f9f291adb9/certificate/nondebug/ZIP/ELF checks and confirmed all four approved Firebase public values are in actual installed resources. Main firstInstallTime preserved, no owner logout/data clear/private screenshot; test .usbtest absent. Thus earlier main12/no-public-config statements are historical. Actual backend registration/reminder queue, further lifecycle/tap and independent release gates remain open.
