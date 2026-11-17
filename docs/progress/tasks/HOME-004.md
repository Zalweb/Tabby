# HOME-004 — Reminder sent state and closed-app delivery are unreliable

```json task-metadata
{
  "id": "HOME-004",
  "area": "home-and-notifications",
  "title": "Reminder sent state and closed-app delivery are unreliable",
  "milestone": "M1",
  "priority": "P2",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "0dfab2d69af69cce91cf4640644104b8a477e0b4",
  "updated_at": "2026-11-04T06:10:00+08:00",
  "audit_ids": [
    "AUD-20261031-036"
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
    "docs/progress/tasks/HOME-004.md",
    "docs/plans/IMPLEMENTATION.md",
    "docs/progress/tasks/INT-001.md",
    "docs/progress/tasks/LED-001.md",
    "docs/progress/tasks/LED-003.md",
    "docs/verification/VER-GRP-001.md",
    "docs/verification/VER-GRP-002.md",
    "docs/verification/VER-GRP-003.md",
    "docs/progress/tasks/PAY-001.md",
    "docs/progress/tasks/HOME-003.md",
    "docs/progress/tasks/AND-001.md",
    "docs/verification/VER-HOME-003.md",
    "docs/verification/VER-PAY-001.md",
    "docs/verification/VER-HOME-004.md",
    "docs/verification/VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP.md",
    "docs/verification/VER-QA-001-LOCAL-HTTP-M1-GUARDS.md",
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
    "docs/**",
    "android/**"
  ],
  "verification": [
    "VER-HOME-004",
    "VER-HOME-005",
    "VER-M1-ACCEPTANCE-REVIEW",
    "VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP",
    "VER-QA-001-LOCAL-HTTP-M1-GUARDS",
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

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-036). Primary owner role: Mobile agent.

- Problem: Reminder sent state and closed-app delivery are unreliable.
- Impact: UI claims delivery before server acceptance; realtime requires a running connection.
- Implement: Await queue acceptance, show sent/pending/failure accurately and add account-bound background push delivery.
- Acceptance: Offline/rejected sends do not claim sent; closed app receives accepted reminders and tap opens authorized target.
- Starting point: [source](../../../lib/features/tabs/application/tabby_providers.dart).

## Implemented

Current result (2026-11-01T04:46:10.723Z): Reminder submission already awaits durable server acceptance with stable retries. This follow-up adds private account-bound device registration/revocation, token-specific leased jobs, a backend OAuth/FCM HTTP v1 worker and an Android data-message receiver. Native display is disabled before registration/revocation awaits and activates only after acknowledgment; old-account/binding messages are discarded. Jobs recheck opt-in, expiry, active membership and actual pair debt, bound retries and prevent stale lease/token failures from removing a replacement. Generic private lock-screen alerts carry no financial content. Cold/warm taps wait for authentication/router startup and re-read active tab/group membership. Missing configuration and remote failures leave local alarms/inbox available and show a background-reminder availability notice.

## Remaining and unverified

Emulator result (2026-11-04T06:05:00+08:00): reminder scheduling produced no observed notification while the app was backgrounded (checked at least 33 seconds after due) or force-stopped (checked 45 seconds after due); a scheduled receiver alarm remained pending. This is a failed observation window, not a delivery pass. Repeat with sufficient inexact-alarm allowance and inspect receiver/logcat/notification history. Evidence: [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-11-01T04:46:10.723Z): Firebase project/app identifiers, backend secrets, scheduler and Edge deployment are not configured or tested. Full Supabase fresh/upgrade/HTTP/auth/RLS integration, real Firebase acceptance and Android allow/deny, background/closed/force-stop/reboot/tap/locked/account-switch/offline-logout/token-rotation journeys remain unverified. Token changes while closed reconcile on next foreground; registrations expire after one day without renewal. Failed remote revocation keeps native display off and remains retryable. Android only; remote iOS/web not wired. No deployment/release approval.

Superseding local HTTP result (2026-11-04): the prior throttle gap is fixed server-side. Exact replay returns 200; changed payload returns 400; new operation IDs inside six hours return HTTP 429 / `PT429` and commit no notification. Acceptance resumes after six hours. A concurrent distinct-operation double tap returns one 200 and one 429 with one committed notification. Closed-app delivery and physical-device behavior remain unverified.

## Verification results

API 37 emulator HOME-004 probe: both scheduled entries were created, but no matching notification appeared in `dumpsys notification` by the recorded observation times; the force-stop probe receiver alarm remained scheduled. The app process was stopped by force-stop. Background/force-stop delivery did not pass. Evidence: [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

Current result (2026-11-01T04:46:10.723Z): [VER-HOME-005](../../verification/VER-HOME-005.md): Final full Flutter suite passed 423/423 and Dart analysis clean. New focused push/tap plus preference suite passed 23/23, including ten new account-registration/tap regressions. Android debug APK builds; Gradle app:testDebugUnitTest passed two Kotlin envelope/binding tests. Six Node worker tests passed, including real synthetic-key OAuth signing/verification, data-only privacy payload, HTTP error classification, response loss, stale leases and worker request gates. Deno 2.5.6 checked the Edge entry point. Native PostgreSQL 17.11 and PostgreSQL/WASM source subsets passed background role/binding/opt-out/expiry/membership/settlement/retry-limit/token-rotation contracts. Eight independent native service-role workers acquire disjoint ready-job leases; existing financial/reminder concurrency contracts pass.

[VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP](../../verification/VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP.md): first nudge and exact replay returned 200, changed payload and immediate second send returned 400; after 61 seconds HTTP 200 committed a second notification. Six-hour assertion failed. Full Flutter suite passed 650/650; analysis clean.

[VER-QA-001-LOCAL-HTTP-M1-GUARDS](../../verification/VER-QA-001-LOCAL-HTTP-M1-GUARDS.md): HTTP 429 / `PT429` with no extra row inside the six-hour window, acceptance at 6h1s, and concurrent distinct operations yielded one 200/one 429 with one notification. Native eight-session concurrency also admitted one and rejected seven. Flutter analysis and full 650-test suite passed. Local evidence only; push delivery/device gate remains open.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Current handoff (2026-11-04T06:05:00+08:00): keep `implemented`. Investigate local reminder delivery while the Activity is backgrounded and after package force-stop; no notification appeared within the documented windows. Repeat with a longer inexact-alarm window. Physical OEM/FCM checks remain separate.

Current result (2026-11-01T04:46:10.723Z): Continue dependency-ready AUTH-002 recovery/confirmation flows and remaining M1 tasks. Stage the complete migrations/worker/configuration and test real Android/background journeys before verified/complete.

Current handoff (2026-11-04T04:15:13+08:00): the additive `send_tab_reminder_v1` implementation enforces a six-hour sender/tab/recipient window after exact idempotent replay, serializes concurrent distinct requests, and exposes HTTP 429 / SQLSTATE `PT429` as the throttled-attempt contract. The home plan documents this response. Immediate, 5h59m, 6h1s and concurrent tests pass locally. Keep status `implemented`; Firebase/configuration, Auth-issued/live Supabase, closed-app delivery and physical-device gates remain open. Evidence: [VER-QA-001-LOCAL-HTTP-M1-GUARDS](../../verification/VER-QA-001-LOCAL-HTTP-M1-GUARDS.md).

- 2026-11-04T03:56:19+08:00 - Local HTTP M1 follow-up: Follow-up local HTTP evidence confirms operation replay and payload conflict behavior (200 replay, 400 changed payload; one notification) and immediate throttle (400). After 61 seconds a new operation returned 200 and committed a second notification, failing the one-nudge-per-six-hours contract. Correct the API throttle interval and rerun; closed-app/device delivery remains open. Evidence: [VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP](../../verification/VER-QA-001-LOCAL-HTTP-M1-FOLLOWUP.md).

## History

- 2026-11-04T06:05:00+08:00 - API 37 emulator HOME-004 background and force-stop probes produced no observed reminder notification in the observation windows; a scheduled receiver alarm remained. Delivery remains failed/open. See [VER-QA-001-ANDROID-DEVICE-MATRIX](../../verification/VER-QA-001-ANDROID-DEVICE-MATRIX.md).

- 2026-11-04T05:36:22+08:00 - Codex root / Windows claims the API 37 emulator device-matrix tranche for SEC-001, SEC-003, HOME-001..004 and QA-001 on `codex/m1-application-fixes`, base `33a89e8c37394f0e7d4983f98d9e1458982015ea`. Read mandatory docs, security/home plans and task handoffs, existing API37 emulator behavior evidence and Flutter integration harness. Reserve only existing integration_test/test_driver harness plus named task handoffs and VER-QA-001-ANDROID-DEVICE-MATRIX evidence; no dependency changes. Emulator only; no signing, release dispatch, M2, live/production change or physical-device claim.


- 2026-11-04T04:15:13+08:00 - Codex root claims HOME-004 server throttle and concurrency regression on `codex/m1-application-fixes`, base `da5aa3f79b7fe8a9b8dccd5642686bfca1ca2ff9`. Read mandatory docs, HOME-004/QA-001/dependencies, home plan, prior API evidence and reminder SQL/tests. Reserved the six-hour SQL guard, additive migration/snapshot, exact PT429 contract, plan update, native/HTTP regressions and task/evidence updates. No competing claim found; starting tree clean. No production mutation, deployment, publication or device tests.

- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-11-01T04:18:51.852Z — Codex root claims truthful server-acknowledged reminders and account-bound background delivery contracts; base a4b7e701a5e30ced6b8f976c8e7008a1ac5e70a2. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-11-01T04:28:06.150Z — Home, notification-center and tab-detail reminders now show waiting feedback and await explicit server acceptance before success, activity or mascot updates. Offline, rejected, unavailable-contact/uninvolved-pair and stale-session responses never claim sent. Pending request IDs persist in scoped encrypted storage and survive response loss/restart; concurrent taps share a request. New send_tab_reminder_v1 atomically inserts one notification and audit per actor/operation, rejects changed payloads and unauthorized/nondebtor/archived targets, and rate-limits new reminders per pair. Legacy RPC execution/direct reminder insert policy and ambiguous-response insert fallback are removed. Accepted means recipient inbox persistence, not device delivery or read receipt.

Remaining: Account-bound remote background token registration, push outbox/worker/native receiving and cold-launch authorized target handling remain to implement. Real Android closed-app/permission/reboot/logout/tap delivery and full Supabase HTTP/staging/upgrade checks remain unverified. This checkpoint implements acknowledgment only; task remains in_progress. No migration deployed.

Verification: Final full Flutter suite passed 413/413; Dart analysis clean. Six new reminder regressions cover pending UI, provider acknowledgment order, exact server activity identity, rejected/uninvolved pairs, old-account discard, concurrent taps and restart response-loss replay. Focused earlier suite passed 24/24, followed by 6/6 new reminder suite including widget waiting/acceptance regression. Native PostgreSQL 17.11 and PostgreSQL/WASM financial source subsets passed reminder role/idempotence/rate-limit/archive checks. Eight independent native sessions return one accepted reminder and one audit row. Initial PostgreSQL run found an ambiguous tab_id variable; renamed before passing native/WASM runs and synchronized schema_all.sql. Initial Flutter compile found a test helper name collision and old UI assertions that claimed offline sends succeeded; corrected fixtures/assertions. New widget test initially tapped below its default viewport; set an explicit phone viewport and pump scroll completion, then verified the actual tap and pending feedback. Analyzer unused-import/const suggestions fixed before final check. Existing financial native concurrency contracts continue to pass. No live deployment/publication. Next: Continue HOME-004 account-bound background transport and authorized cold-launch taps. Supply environment configuration through deployment tooling without committing secrets; verify actual device and staged delivery before closure.

- 2026-11-01T04:28:07.644Z — Codex root claims account-bound Android background push registration, outbox/worker and authorized cold-launch taps; base 0dfab2d69af69cce91cf4640644104b8a477e0b4. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-11-01T04:46:10.723Z — Reminder submission already awaits durable server acceptance with stable retries. This follow-up adds private account-bound device registration/revocation, token-specific leased jobs, a backend OAuth/FCM HTTP v1 worker and an Android data-message receiver. Native display is disabled before registration/revocation awaits and activates only after acknowledgment; old-account/binding messages are discarded. Jobs recheck opt-in, expiry, active membership and actual pair debt, bound retries and prevent stale lease/token failures from removing a replacement. Generic private lock-screen alerts carry no financial content. Cold/warm taps wait for authentication/router startup and re-read active tab/group membership. Missing configuration and remote failures leave local alarms/inbox available and show a background-reminder availability notice.

Remaining: Firebase project/app identifiers, backend secrets, scheduler and Edge deployment are not configured or tested. Full Supabase fresh/upgrade/HTTP/auth/RLS integration, real Firebase acceptance and Android allow/deny, background/closed/force-stop/reboot/tap/locked/account-switch/offline-logout/token-rotation journeys remain unverified. Token changes while closed reconcile on next foreground; registrations expire after one day without renewal. Failed remote revocation keeps native display off and remains retryable. Android only; remote iOS/web not wired. No deployment/release approval.

Verification: Final full Flutter suite passed 423/423 and Dart analysis clean. New focused push/tap plus preference suite passed 23/23, including ten new account-registration/tap regressions. Android debug APK builds; Gradle app:testDebugUnitTest passed two Kotlin envelope/binding tests. Six Node worker tests passed, including real synthetic-key OAuth signing/verification, data-only privacy payload, HTTP error classification, response loss, stale leases and worker request gates. Deno 2.5.6 checked the Edge entry point. Native PostgreSQL 17.11 and PostgreSQL/WASM source subsets passed background role/binding/opt-out/expiry/membership/settlement/retry-limit/token-rotation contracts. Eight independent native service-role workers acquire disjoint ready-job leases; existing financial/reminder concurrency contracts pass. Initial Kotlin test command lacked Git PATH and failed before compilation; rerun with the documented runtime path passed. Initial analysis brace suggestions fixed. Review added router-readiness fencing for cold taps, group-membership checks, native invalidation during old in-flight registrations, token-specific invalidation to protect replacements, bounded expired-worker retries and settled-debt cancellation. Final analysis/native/WASM checks pass. Existing package_info_plus KGP/Gradle deprecation warnings remain; no dependency-wide upgrade is claimed. No live deployment/publication. Next: Continue dependency-ready AUTH-002 recovery/confirmation flows and remaining M1 tasks. Stage the complete migrations/worker/configuration and test real Android/background journeys before verified/complete.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: android-device, integration-review. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).

- 2026-11-14T03:16:51.639+08:00 — Superseding scoped physical evidence: [QA-013 local native delivery](../../verification/VER-QA-013-ANDROID-NOTIFICATIONS.md) passes4 cases on API36/4KB, including actual foreground inexact alarm posting, account/preference cleanup and package-scoped runtime denial. This does not close background/closed/FCM/reboot/tap/interactive-prompt or independent-review gates; keep implemented.

2026-11-14T14:20:41.074+08:00 — Superseding bounded acceptance: Actual local alarm closed-process/reboot cold payload/draft/PIN accepted on16KB emulator. FCM configuration/delivery and physical OEM authenticated tap checks remain open. See [QA-014](QA-014.md), [QA-015](QA-015.md), [QA-016](QA-016.md), [QA-017](QA-017.md), [QA-018](QA-018.md). Existing broader required checks/state remain unchanged.
