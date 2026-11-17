# HOME-003 — Notification preferences and permissions are disconnected

```json task-metadata
{
  "id": "HOME-003",
  "area": "home-and-notifications",
  "title": "Notification preferences and permissions are disconnected",
  "milestone": "M1",
  "priority": "P1",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "4e9c0066650dd6a78e2f84ce5888152f6a7054f1",
  "updated_at": "2026-11-04T06:10:00+08:00",
  "audit_ids": [
    "AUD-20261031-035"
  ],
  "dependencies": [
    "LED-003",
    "PAY-001"
  ],
  "read_set": [
    "AGENTS.md",
    "docs/INDEX.md",
    "docs/project/INSTRUCTIONS.md",
    "docs/project/DECISIONS.md",
    "docs/progress/STATUS.md",
    "docs/plans/home-and-notifications.md",
    "docs/progress/tasks/HOME-003.md",
    "docs/plans/IMPLEMENTATION.md",
    "docs/progress/tasks/INT-001.md",
    "docs/progress/tasks/LED-001.md",
    "docs/progress/tasks/LED-003.md",
    "docs/verification/VER-GRP-001.md",
    "docs/verification/VER-GRP-002.md",
    "docs/verification/VER-GRP-003.md",
    "docs/verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md",
    "integration_test/android_device_matrix_seed_test.dart",
    "integration_test/android_device_matrix_test.dart",
    "test_driver/integration_test.dart"
  ],
  "coverage": [
    "lib/features/home/**",
    "test/**",
    "supabase/**",
    "lib/core/**",
    "pubspec.yaml",
    "pubspec.lock",
    "lib/**",
    "scripts/**",
    "docs/**"
  ],
  "verification": [
    "VER-HOME-003",
    "VER-HOME-005",
    "VER-M1-ACCEPTANCE-REVIEW",
    "VER-QA-001-ANDROID-DEVICE-MATRIX"
  ],
  "required_checks": [
    "regression",
    "android-device"
  ],
  "acceptance_review": {
    "local_review": "passed",
    "at": "2026-11-01T23:41:43.428Z",
    "commit": "14d1cd6d262e9ce39992e8d3258a358ed318d366",
    "scope": "Acceptance inventory and local regression review only; independent/external acceptance is not established",
    "pending_checks": [
      "android-device",
      "integration-review"
    ]
  }
}
```

## Scope and acceptance

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-035). Primary owner role: Mobile agent.

- Problem: Notification preferences and permissions are disconnected.
- Impact: Alerts may be absent on fresh installs or persist after disable/logout.
- Implement: Request permission from enable flow, enforce account-scoped preferences and cancel alarms/token association on logout.
- Acceptance: Fresh permission allow/deny, disable preferences and logout each produce the expected alert behavior.
- Starting point: [source](../../../lib/core/services/tabby_notification_service.dart).

## Implemented

Current result (2026-11-01T04:46:10.723Z): Account-scoped notification opt-in still waits for OS permission and atomic preference persistence; master/category switches gate foreground/local alerts, collision-safe IDs and missing-schedule reconciliation remain. Background registration and native scope now follow the same active account/session and reminder preference. Logout clears local/native display before remote revocation, and background cancellation still runs if local registry handling fails. Captured sessions prevent delayed cleanup from signing out a new account. Missing remote setup is surfaced separately from local opt-in.

## Remaining and unverified

Emulator result (2026-11-04T06:05:00+08:00): notification permission granted + preference enabled created a pending reminder alarm; disabling preferences removed it. With permission denied after package installation, the platform API returned false and no alarm was produced. Re-granting permission reproduced the enabled/disabled result. Physical Android channel settings remain unverified. Evidence: [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-11-01T04:46:10.723Z): Actual Android permission/channel, alarm cancellation, background delivery, reboot, process death, storage behavior and account-switch/offline logout remain unverified. Registry retention/scale remains AND-004. Background backend/FCM configuration and deployment are absent; source/mocks/builds cannot close device checks.

## Verification results

API 37 emulator probes measured `(permission, enabled-alarm, disabled-alarm)` as `(false,false,false)` while OS permission was denied and `(true,true,false)` after permission grant. Emulator-only pass for the tested permission and preference gates. See [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-11-01T04:46:10.723Z): [VER-HOME-005](../../verification/VER-HOME-005.md): Final full Flutter suite passed 423/423 and Dart analysis clean. New focused push/tap plus preference suite passed 23/23, including ten new account-registration/tap regressions. Android debug APK builds; Gradle app:testDebugUnitTest passed two Kotlin envelope/binding tests. Six Node worker tests passed, including real synthetic-key OAuth signing/verification, data-only privacy payload, HTTP error classification, response loss, stale leases and worker request gates. Deno 2.5.6 checked the Edge entry point. Native PostgreSQL 17.11 and PostgreSQL/WASM source subsets passed background role/binding/opt-out/expiry/membership/settlement/retry-limit/token-rotation contracts. Eight independent native service-role workers acquire disjoint ready-job leases; existing financial/reminder concurrency contracts pass.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Current handoff (2026-11-04T06:05:00+08:00): keep `implemented`; test Android channel-level block/allow, account switching and physical-device behavior before verification. The emulator confirmed OS permission false prevents alarm creation and app preference disable cancels a pending alarm.

Current result (2026-11-01T04:46:10.723Z): Continue AUTH-002 and M1 implementation; run the physical permission/category/master/logout/reboot matrix and staged background delivery before closure.

## History

- 2026-11-04T06:05:00+08:00 - API 37 emulator permission-state/preferences passed: denied permission returned false/no alarm; granted permission enabled the alarm; disabled preference canceled it. Evidence: [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

- 2026-11-04T05:36:22+08:00 - Codex root / Windows claims the API 37 emulator device-matrix tranche for SEC-001, SEC-003, HOME-001..004 and QA-001 on `codex/m1-application-fixes`, base `33a89e8c37394f0e7d4983f98d9e1458982015ea`. Read mandatory docs, security/home plans and task handoffs, existing API37 emulator behavior evidence and Flutter integration harness. Reserve only existing integration_test/test_driver harness plus named task handoffs and VER-QA-001-ANDROID-DEVICE-MATRIX evidence; no dependency changes. Emulator only; no signing, release dispatch, M2, live/production change or physical-device claim.


- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-11-01T03:59:52.518Z — Codex root claims account-scoped notification permission/preferences, serialized lifecycle cancellation and collision-safe scheduling registry; base 4e9c0066650dd6a78e2f84ce5888152f6a7054f1. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-11-01T04:18:45.687Z — Notification opt-in now awaits OS permission and an atomic account-scoped preference write. Fresh accounts default off and never inherit global or other-account notification preferences. Foreground banners and device alerts respect master/category switches. A serialized account/session controller cancels alarms on logout/account changes, rejects old-session asynchronous work, persists collision-safe IDs, deduplicates acknowledged device writes and restores missing scheduled requests. Logout retains its original session identity so delayed cleanup cannot sign out a newly signed-in account. Plugin failure does not prevent authentication logout; failures remain explicit settings errors.

Remaining: Real Android permission allow/deny, logout cancellation, reboot, process death, channel settings and account switching remain unverified; no connected device. Account-bound background push/token registration and cold-launch tap authorization remain HOME-004 work. Local scheduling success is not delivery evidence. Notification registry/cache retention and scale remain AND-004. No deployed changes or release approval.

Verification: Final full Flutter suite passed 407/407 and Dart analysis reported no issues. Thirteen new regressions cover scoped migration/defaults, malformed settings isolation from security loading, permission denial, delayed opt-in acknowledgment, persistence failure, category/master cancellation, forced ID collisions, duplicate/failed device writes, missing OS requests, delayed account transition and same-account new-session invalidation. Focused notification suite initially passed 12/12 before the additional persistence regression; focused existing UI suite passed 20/20 after updating obsolete default/label assertions. Android debug APK built successfully; adb reports no devices. Initial analysis brace/non-null suggestions were fixed. Initial test compile rejected repeated underscore parameters under the repository Dart language version; corrected. Initial full run found two old UI assertions expecting notifications enabled by default and the unsupported Push Notifications wording; tests now assert fresh opt-in denial and Device notifications. Final full suite passes. Build emits existing package_info_plus Kotlin Gradle Plugin future-compatibility warning; no dependency upgrade or production artifact is claimed. No live deployment/publication. Next: Continue HOME-004 truthful reminder send acknowledgment and account-bound background delivery, then dependency-ready M1 tasks. Run physical Android allow/deny, category/master disable, account switch/logout/reboot before verified/complete.

- 2026-11-01T04:46:10.723Z — Account-scoped notification opt-in still waits for OS permission and atomic preference persistence; master/category switches gate foreground/local alerts, collision-safe IDs and missing-schedule reconciliation remain. Background registration and native scope now follow the same active account/session and reminder preference. Logout clears local/native display before remote revocation, and background cancellation still runs if local registry handling fails. Captured sessions prevent delayed cleanup from signing out a new account. Missing remote setup is surfaced separately from local opt-in.

Remaining: Actual Android permission/channel, alarm cancellation, background delivery, reboot, process death, storage behavior and account-switch/offline logout remain unverified. Registry retention/scale remains AND-004. Background backend/FCM configuration and deployment are absent; source/mocks/builds cannot close device checks.

Verification: Final full Flutter suite passed 423/423 and Dart analysis clean. New focused push/tap plus preference suite passed 23/23, including ten new account-registration/tap regressions. Android debug APK builds; Gradle app:testDebugUnitTest passed two Kotlin envelope/binding tests. Six Node worker tests passed, including real synthetic-key OAuth signing/verification, data-only privacy payload, HTTP error classification, response loss, stale leases and worker request gates. Deno 2.5.6 checked the Edge entry point. Native PostgreSQL 17.11 and PostgreSQL/WASM source subsets passed background role/binding/opt-out/expiry/membership/settlement/retry-limit/token-rotation contracts. Eight independent native service-role workers acquire disjoint ready-job leases; existing financial/reminder concurrency contracts pass. Initial Kotlin test command lacked Git PATH and failed before compilation; rerun with the documented runtime path passed. Initial analysis brace suggestions fixed. Review added router-readiness fencing for cold taps, group-membership checks, native invalidation during old in-flight registrations, token-specific invalidation to protect replacements, bounded expired-worker retries and settled-debt cancellation. Final analysis/native/WASM checks pass. Existing package_info_plus KGP/Gradle deprecation warnings remain; no dependency-wide upgrade is claimed. No live deployment/publication. Next: Continue AUTH-002 and M1 implementation; run the physical permission/category/master/logout/reboot matrix and staged background delivery before closure.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: android-device, integration-review. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).

- 2026-11-14T03:16:51.639+08:00 — Superseding scoped physical evidence: [QA-013 local native delivery](../../verification/VER-QA-013-ANDROID-NOTIFICATIONS.md) passes4 cases on API36/4KB, including actual foreground inexact alarm posting, account/preference cleanup and package-scoped runtime denial. This does not close background/closed/FCM/reboot/tap/interactive-prompt or independent-review gates; keep implemented.
