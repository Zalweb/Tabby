# Mobile audit repair changelog

```json verification-metadata
{
  "id": "BUG_FIX_CHANGELOG",
  "task_ids": [
    "QA-003",
    "QA-004",
    "QA-005",
    "QA-006",
    "QA-007",
    "QA-008",
    "QA-010",
    "QA-011",
    "QA-012",
    "QA-013"
  ],
  "timestamp": "2026-11-14T03:16:51.639+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Android/iOS source repairs and local Windows fixtures; summary links the authoritative task and verification record.",
  "commands": [
    "See VER-QA-003-MOBILE.md for reproduced failures and executed verification",
    "See VER-QA-005-SOCIAL.md for latest client-only verification",
    "See VER-QA-006-FRIENDSHIP.md for latest SQL authorization/fresh-upgrade evidence"
  ],
  "checks": [
    {
      "category": "repair-changelog",
      "outcome": "passed"
    }
  ]
}
```

## Expected and actual results

### Android22 expense entry checkpoint — 2026-11-17T19:32:43.704Z

[QA-032](VER-QA-032-EXPENSE-ENTRY.md) delivers existing-tab Add/View/Cancel, contextual duplicate review/override and plain custom shares (450→0/150/300). Both post-delivery review fixes are included in signed universal1.0.4+22: replacement-person lookup and zero-remaining SDK allocations.903 full tests, clean analysis,39 isolated expense cases,12 SDK wire cases and16 physical Android cases pass. Exact installed APK SHA2562c007275b283361fc647b1c48e8c72dafd2b2b57db1a90a5c921bcc27495502a matches the approved production certificate; exact same bytes start on native x86_64/16KB emulator. Original tablet install identity/login/data/.usbtest preserved, no owner test seed; temporary .entrytest removed. [Results](QA-032-results.json), [source](QA-032-v22-source-manifest.json), [user summary](../plans/expense-entry-update-summary.md).

This private Android evidence does not establish public release approval, independent integration review, actual two-device Realtime delivery, or an iOS device pass. Advanced M2 tax/service flags, confirmed history, backend deployment and billing remain unchanged. QA-034 owns current iOS parity/unsigned artifact work separately; unverified iOS changes are excluded from Android22. Native/build/device reservation is released, next normal Android23+.

### Superseding physical local notification acceptance — 2026-11-14T03:16:51.639+08:00

[QA-013](VER-QA-013-ANDROID-NOTIFICATIONS.md) passes4 actual native cases: immediate OS posting, account/preference cleanup, future inexact alarm delivery after 5063ms with exact access=false, and revoked runtime permission suppressing immediate/scheduled alerts. Test-package permission was restored.65 Node/clean analysis pass; production/host source unchanged from the prior736 Flutter checkpoint. [Source delta/results](QA-013-results.json). Native session checkpoint dec17d0 is committed.

This supersedes scheduling-only limits only for the foreground/awake local alarm scope. Closed/background/force-stop/reboot/taps/FCM/OEM restrictions, actual provider/Storage/wallet,16KB runtime, signed upgrade/exact artifact and review remain open. iOS stays deferred under current Android-only instruction. Production remains NO-GO; no cloud, real-data or release operation.

### Superseding Android fixture checkpoint — 2026-11-14T03:06:06+08:00

QA-011 receiving source is committed0b03f828. The previous unavailable-tablet blocker is resolved: [fresh physical smoke/matrix](VER-QA-009-ANDROID-DEVICE.md) pass on API36/4KB, plus [22 receiving/15 auth native fixture cases](VER-QA-012-ANDROID-SESSIONS.md). A first false-pass report is rejected; synchronous registration and clean-output/named-case validation repair the test harness. Full736 Flutter/64 Node/clean analysis pass. [Current source/results](QA-012-results.json) preserve exact dirty-tree/run scope.

Production remains NO-GO: actual provider/Storage/wallet, notification delivery/taps, broader restore/picker/low-memory,16KB runtime, signed upgrade/exact release candidate and integration review remain open. The current user requests Android-only testing; iOS runtime is deferred for this phase and not passed. No live backend mutation, deployment, public release or production-package clearing occurred. Historical no-device/older-count statements below retain their dates and are superseded only within this local-fixture scope.

### Superseding committed checkpoint and receiving review — 2026-11-14T01:22:33.161+08:00

Authorized local checkpoint2ac4134 succeeded with a clean tree immediately afterward; [checkpoint evidence](VER-QA-010-CHECKPOINT.md) records61 Node checks and staged dependency/credential exclusion validation. The subsequent [QA-011 receiving repair](VER-QA-011-RECEIVING.md) fixes obsolete friend/payment/owner/QR views, cached actions/cache and clipboard acknowledgment failures.24 new/54 focused-neighbor and736 full Flutter pass, clean analysis/debug packaging; [latest source/results](QA-011-results.json) identify this patch. It awaits the next authorized local commit. Independent review, actual provider/native/iOS/exact signed release gates remain open; production NO-GO. QA-009 still has no connected tablet.

### Superseding auth completion review — 2026-11-14T00:45:38.628+08:00

[QA-008](VER-QA-008-AUTH.md) repairs obsolete login/signup completions restoring auth/profile flags, disposed signup completion and unhandled optional preference writes. Public SDK event acknowledgment preserves legitimate completion. Final15 focused/712 full Flutter, clean analysis and isolated Android debug packaging62.4s pass; [latest source/results](QA-008-results.json) identify current mobile source. Backend/native/tooling remain QA-007 scope. A new paired-tablet TLS advertisement makes native preflight actionable; identity/device execution is not yet established. Production remains NO-GO with provider/iOS/independent review/exact signed release gates open.

### Superseding pair concurrency review — 2026-11-13T18:57:37.739+08:00

[QA-007](VER-QA-007-SOCIAL-CONCURRENCY.md) repairs duplicate opposing pending requests and same-direction duplicate-key failures with canonical-pair transaction serialization. Eight native races across50→52,51→52,fresh52 and standalone snapshot pass, retaining consent/private-access regressions. Full local API fresh52/pending34 passes. [Latest source/results](QA-007-results.json) supersede only local SQL inputs; mobile source remains unchanged. Production remains NO-GO, both local security/social migrations are unapplied, and native/platform/provider/independent review/signed release gates stay open.

### Superseding friendship authorization review — 2026-11-13T18:49:13.170+08:00

[QA-006](VER-QA-006-FRIENDSHIP.md) reproduces a local source consent bypass: direct accepted-friendship INSERT grants private profile/receiving/avatar access. An additive RPC-only insertion migration repairs it, plus declined-request resend42702 and acceptance-notification42703 failures. Executable snapshot separators/trigger are synchronized. Fresh51-migration,50→51 upgrade and standalone snapshot authorization tests pass; full local PostgREST fresh51/pending33 and independent-session financial subset pass. [Latest source/results](QA-006-results.json) record final hashes. QA-005697 client tests/clean analysis/debug build apply to unchanged mobile source. Production remains NO-GO: this security repair is not deployed, effective deployed policies need authorized review, existing rows remain untouched, and native/platform/provider/independent review/release gates remain open. No production exposure or remediation is inferred from local source alone.

### Superseding social review — 2026-11-13T18:36:38.648+08:00

[QA-005 evidence](VER-QA-005-SOCIAL.md) records repaired old-session friend results, validated decision acknowledgments, account-bound friend sheets, edited-ID identity mismatches and opposing pending response taps. Final full Flutter697/697, clean analysis and isolated Android debug build19.9s pass. [Current source/results](QA-005-results.json) identify this newer dirty source. SDK dispatch token-switching was investigated and not reproduced; no transport pinning claim. Backend contracts are unchanged. Full source review remains active; real native/provider/independent review and exact signed release gates remain open. Production remains NO-GO.

### 2026-11-13T18:07:00+08:00 — Payment/session/read-order and accessibility follow-up

P1: older same-session ledger refreshes could replace a newer confirmed payment/balance; successful decisions could report completion after account changes during persistence; asynchronous confirmation could pop a newer dialog; financial details/media/reminder sheets retained old-session content. [QA-004](../progress/tasks/QA-004.md) adds monotonic ledger read revisions, decision/reset invalidation, post-await session checks, exact owning-route dismissal and existing AccountDraftGuard coverage for financial sheets. The default repository and wire contracts remain unchanged.

P2: a fixed receipt panel overflowed at800x600, and the tab summary/history heading overflowed at360x640 with200% text. The summary and receipt content now scroll within available height; history labels wrap and ledger records remain lazy/paged. Tests retain original size/text/visibility assertions. History/correction tests explicitly target the ledger scroll area after adding the header scroll area.

Files: [provider](../../lib/features/tabs/application/tabby_providers.dart), [decision UI](../../lib/features/tabs/presentation/payment_decision_actions.dart), [detail/media/layout](../../lib/features/tabs/presentation/tab_detail_screen.dart), [payment tests](../../test/features/payment_decisions_test.dart), [receipt tests](../../test/features/receipt_revisions_test.dart), [history tests](../../test/features/history_rendering_test.dart) and [correction tests](../../test/features/expense_revision_projection_test.dart). Initial reproduced failures and superseding28 focused/670 full passing tests, clean analysis and native-build limits are in [VER-QA-004-MOBILE](VER-QA-004-MOBILE.md). Native account/lifecycle acceptance and independent review remain open; no release or deployment.

### 2026-11-13T16:30:00+08:00 — Immutable receipt/proof replay (P1)

Expected: after a financial RPC commits and its reply is lost, the same persisted command can replay without changing the proof or duplicating the payment/expense. Actual before repair: [ReceiptAttachmentService](../../lib/core/services/receipt_attachment_service.dart) uploaded the same operation path with `upsert:true` before every RPC replay. Referenced objects correctly reject updates under existing RLS, so replay stopped at403 before reaching the idempotent financial RPC. An unreferenced same-path/different-byte upload could instead overwrite the earlier bytes.

Fix: create-only uploads. An explicit duplicate response triggers an authorized download; only exact matching bytes and the initiating current session acknowledge the object. Changed bytes, read denial, other upload failures and stale sessions fail without overwriting or acknowledging. Both direct resolution and durable upload use the same helper. Retained empty/over-5-MB payloads fail locally. Upload fallback logs no longer interpolate raw provider errors. No Storage/RPC privileges or money-confirmation rules were changed.

Regression: [receipt_upload_transport_test.dart](../../test/features/receipt_upload_transport_test.dart) uses the installed real Supabase client against loopback HTTP/multipart fixtures. Eight scenarios cover lost temporary file, immutable referenced replay, different-byte conflict, ambiguous upload acknowledgment, denied duplicate read, ordinary upload denial, account change during download and invalid retained sizes. The fixture preserves object bytes and checks actual requests/authorization headers. Neighboring [proof](../../test/features/payment_proof_test.dart), [receipt revision](../../test/features/receipt_revisions_test.dart), session and retry tests pass. The initial fixture endpoint mistake and corrected run are recorded in [evidence](VER-QA-003-MOBILE.md).

Status: implemented and locally regressed under [PAY-002](../progress/tasks/PAY-002.md), [PAY-003](../progress/tasks/PAY-003.md) and [QA-003](../progress/tasks/QA-003.md). Real Storage RLS/response-loss/device replay remains unverified; no deployment.

### 2026-11-13T16:30:00+08:00 — iOS local notification delegate (P1 for iOS)

Expected: iOS forwards foreground presentation and notification responses through Flutter's registered notification plugin. Actual source omitted the UserNotifications delegate in [AppDelegate.swift](../../ios/Runner/AppDelegate.swift), although Dart initialization and plugin callbacks existed. The installed flutter_local_notifications22.3.1 [iOS setup](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1#-ios-setup) requires the launch delegate; installed plugin source confirms its presentation/response handlers depend on that boundary.

Fix: import UserNotifications and assign its current center's delegate to the FlutterAppDelegate before returning from launch. Existing UIScene/implicit-engine plugin registration stays intact. [Native configuration regression](../../test/ios_notification_configuration_test.dart) failed before repair and passes afterward. This is static configuration evidence; no Swift build, iPhone foreground/background/cold-tap run, APNs setup or remote iOS push support is claimed. Owner: QA-003; next action is Mac/iPhone native acceptance.

### 2026-11-13T16:30:00+08:00 — Stale mobile publication regression (P2)

Expected: mobile tests enforce the accepted manual Android candidate release contract and keep unsigned iOS packaging private. Actual [legacy test](../../test/release_workflow_test.js) required automatic `workflow_run` publication and public unsigned IPA aliases. The actual workflows already implement the accepted fail-closed/manual gates in [release instructions](../releases/README.md). This pre-existing test failed in the additional audit run.

Fix: four mobile workflow checks now require private platform build artifacts, signed Android candidate verification, private unsigned iOS packaging, explicit manual main/protected publication, run/commit provenance, artifact/evidence verification before publication and no unsigned iOS artifact in the Android publisher. Existing [release verifier behavioral tests](../../scripts/android-release.test.cjs) remain unchanged. No workflow was enabled or weakened. An intermediate JS interpolation syntax error was fixed before the final passing61/61 Node run.

### 2026-11-13T16:30:00+08:00 — Stale architecture statement (P3)

Actual [architecture document](../project/ARCHITECTURE.md) still described transactional Drift as planned. Current adapter/database and executable encrypted-storage regressions prove integration exists. Added a dated superseding source description and retained the original foundation text as history. No storage rewrite or dependency change.

## Evidence

[VER-QA-003-MOBILE](VER-QA-003-MOBILE.md) records the baseline, six reproduced failures, corrected fixture/test attempts, targeted24/24 and full659/659 Flutter passes, clean analysis, Node61/61, native/PGlite contracts, current full local public-schema HTTP checks and isolated Android packaging. [Sanitized results](QA-003-local-results.json) and [source hashes](QA-003-source-manifest.json) identify the dirty revision. Results are local unless explicitly labeled Azure GET probes; none constitute release approval.

## Limits and next action

All changes remain local and uncommitted alongside preserved pre-existing work. Independent review/integration, real mobile/platform/provider journeys and signed-candidate verification remain open. See [remaining issues](REMAINING_ISSUES.md); the [readiness decision](PRODUCTION_READINESS_REPORT.md) remains NO-GO.

## 2026-11-14T14:20:41.074+08:00 — Acceptance/tooling and approved security deployment

Android artifact verifier now detects unsafe RELRO writable tails on16KB pages; five regression cases cover rejection and legitimate padding. Device builds regenerate mode-specific plugin registration after release/debug transitions. Native16KB encrypted-storage and closed/reboot notification fixtures execute against Android, and the live Realtime fixture verifies saved/read-back/restored state. Approved friendship RPC-only/pair-lock SQL was applied to Azure migration destination after encrypted backup/rehearsal, then24 real consent checks passed. Source SQL itself was unchanged. See [Actual Android 16KB encrypted storage and session acceptance](VER-QA-014-16KB.md), [Private production signing and Android staging upgrade rehearsal](VER-QA-015-SIGNING.md), [Actual notification cold launches after process death and emulator reboot](VER-QA-016-LIFECYCLE.md), [Approved Azure friendship security patch and live consent acceptance](VER-QA-017-DEPLOYED.md), [Firebase sign-in and project-quota setup blocker](VER-QA-018-FIREBASE.md). No new production Dart behavior change in this batch. Firebase setup remains incomplete at Google project quota.

## 2026-11-14T14:33:57.367+08:00 — Signed financial storage upgrade rehearsal

Actual release/AOT v7 seed and same-production-key v8 upgrade verified the production default encrypted ledger factory, all10000 synthetic history entries/IDs/order/centavos, an unchanged durable operation ID/payload, secure draft and PIN, same secure encryption key and owner isolation. All runtime checks are explicit exceptions rather than release-disabled assertions. A normal-main v9 restoration APK was built and validated before any fixture installation, then installed/launched in finally. Every install rechecked qemu1/x86_64/16384-byte pages, exact APK bytes/certificate, version and unchanged Android appId. Starting v6 APK bytes were pulled and matched the exact known private baseline before replacing it. See [release-signed encrypted storage upgrade](VER-QA-019-SIGNED-STORAGE.md). This is a new-key synthetic release-signed storage upgrade rehearsal, not an upgrade from either old debug-signed APK, backend command replay, real financial operation, full app/candidate acceptance or ARM64 runtime. Firebase project choice/quota, provider/live journeys and independent integration review remain open. The personal tablet was never targeted; iOS deferred. The earlier generic signed-financial-storage rehearsal gap now has bounded new-key emulator acceptance; legacy/debug transition and final exact candidate gates remain open.

## 2026-11-14T16:06:03.377+08:00 — Clean physical live-testing installation

User-authorized normal release v1.0.4+10 is now installed fresh on the Lenovo tablet, signed out at onboarding. Exact installed bytes match SHA256 9b5ccd7554c90c9248ef65dcc2e50e16722e075609746be9a2e285c31f540751. APK scan found no selected fixture credentials, synthetic seed markers or packaged ledger database. Temporary test app/data removed after five native smoke cases and real SDK Auth/RLS/Realtime pass;76 Node checks, analysis, four anonymous probes and same-APK16KB startup pass. [Evidence](VER-QA-021-CLEAN-TABLET.md), [results](QA-021-results.json). User will use an existing account; its cloud history is retained. Signup disabled; Google/FCM/providers/final synchronization/cutover/full journeys/review remain open. This private acceptance install is not production readiness or public publication.

## 2026-11-17T07:04:59.293Z — Google browser handoff and Azure provider repair (QA-022)

Root cause: signInWithOAuth's browser-launch acknowledgment was treated as completed authentication; login immediately displayed a false pending error and ignored failed launch. Missing native-token fallback could also launch twice during an intermediate repair. The self-hosted provider lacked its explicit redirect URI; once registered by the user, its old Web-client secret was independently rejected as invalid_client.

Fix: typed authenticated/browserOpened/cancelled repository results, exact acknowledged native Session, neutral browser instructions, one fallback, and mounted/attempt/session-scoped terminal callback error observation. Existing generation guards retained. Reviewed operator adds only the approved callback and matching existing-client secret, backs up/recovery-checks encrypted configuration and recreates Auth only. Future application configuration retains the encrypted current-provider override/callback. Affected sources: login_screen.dart, supabase_tabby_repository.dart, configure-application.py, configure-google-callback.py and focused/native contract tests.

Observed: corrected original source fails2 UI assertions; intermediate duplicate-browser assertion reproduced then fixed. Final29 focused/747 auth-only full/759 integrated Flutter,76 Node,5 operator guards, clean analysis and48 physical fixture cases pass. Real manual Google sign-in now opens Home with a new server session/token200. Commit487470b; [full evidence and limits](VER-QA-022-GOOGLE.md). Normal12 same-key update preserves owner data. Independent review/full release acceptance remain open.

## 2026-11-17T07:51:50.737Z — Configured Firebase Android resources and keyless sender

Actual Firebase-defined APK build failed because AGP9 disables custom resValues by default; app now explicitly enables only that feature. Configured isolated build and actual normal13 installed-resource check pass. Sender key creation was rejected by Google policy, so the existing worker now accepts strictly validated Azure external-account federation while retaining legacy service-account support. No policy weakening or downloadable key.12 worker regressions/32 neighboring Node/3 operator guards and actual edge-runtime authentication pass. Live native FCM background/stopped-process delivery and suppression checks pass. [Evidence](VER-QA-018-KEYLESS.md) records the failed build/harness attempts and remaining full-queue/review limits.


## Notification ledger cursor checkpoint — 2026-11-17T09:42:46.633Z

Real spare-Google notification testing exposed Tab not found. Initial route-readiness repair failed physically; isolated runtime then proved Invalid tab cursor because the SDK defaulted descending. Production headers now explicitly ascend, and notification navigation awaits a scoped exact target. Actual SDK cursor regression,24 focused tests,754-test owned snapshot/full analysis and819-test integrated UI run pass. Signed normal15 contains exact functional source hashes and is installed in place, retaining data/session. Actual queue/group native posting is proved; corrected final tap, further lifecycle and independent review remain open. Synthetic sender access is retired; no existing financial history changed or scheduler/public release activated. [Current evidence](VER-QA-027-NOTIFICATION-TAP.md).


## Native reminder handoff checkpoint — 2026-11-17T10:31:22.718Z

The actual router error and closed-app Home fallback are now corrected by explicit Android link ownership plus a Dart-listener handshake before destructive intent consumption. Final real warm/cold drawer taps show the correct existing spare-account group/PHP1.00; native4 regressions pass. Signed normal16 is installed in place with exact digest02dd7199462e1ffc1b24372aa1e95c8b76a8b893475899982220cd3c9e240f8f, preserving owner data/session and reserved test packages. Final live financial integrity passes, sender remains retired and pending jobs0. This supersedes older pending-tap/main15 notes. Independent review/clean final candidate, remaining lifecycle/backend/cutover and exact16KB runtime remain open; no scheduler/public release. [Current evidence](VER-QA-027-NATIVE-INTENTS.md).
