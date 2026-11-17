# Tabby documentation index

## Mandatory session reading

[Root agent instructions](../AGENTS.md) → [project instructions](project/INSTRUCTIONS.md) → [decisions](project/DECISIONS.md) → [master plan](plans/IMPLEMENTATION.md) → [current progress](progress/STATUS.md) → relevant area plan/task/dependency evidence.

## Project

- [Architecture and baseline](project/ARCHITECTURE.md)
- [Design and language](project/DESIGN.md)
- [Mascot icon assets and generation prompts](assets/mascot-launcher-prompts.md), [tablet update verification](verification/VER-QA-023-MASCOT.md)
- [Responsive login and mascot hero verification](verification/VER-QA-024-LOGIN.md)
- [Android audit register](audits/2026-10-31-android-review.md)
- [Verification protocol](verification/README.md)
- [Android and iOS production readiness report](verification/PRODUCTION_READINESS_REPORT.md)
- [Mobile repair changelog](verification/BUG_FIX_CHANGELOG.md)
- [Remaining mobile issues and acceptance gates](verification/REMAINING_ISSUES.md)
- [Current mobile audit evidence](verification/VER-QA-003-MOBILE.md), [sanitized local results](verification/QA-003-local-results.json) and [tested source hashes](verification/QA-003-source-manifest.json)
- [Payment/session/accessibility follow-up](verification/VER-QA-004-MOBILE.md) and [current source/result manifest](verification/QA-004-results.json)
- [Account-bound social follow-up](verification/VER-QA-005-SOCIAL.md) and [latest source/results](verification/QA-005-results.json)
- [Friendship consent and fresh/upgrade evidence](verification/VER-QA-006-FRIENDSHIP.md) and [latest SQL/source results](verification/QA-006-results.json)
- [Friend-request native concurrency](verification/VER-QA-007-SOCIAL-CONCURRENCY.md) and [latest source/results](verification/QA-007-results.json)
- [Session-bound auth completion](verification/VER-QA-008-AUTH.md) and [latest mobile source/results](verification/QA-008-results.json)
- [Historical Android transport blocker](verification/VER-QA-009-ANDROID-TRANSPORT.md) and [superseding physical smoke/matrix results](verification/VER-QA-009-ANDROID-DEVICE.md)
- [Android session fixtures and runner false-pass repair](verification/VER-QA-012-ANDROID-SESSIONS.md), [source/results](verification/QA-012-results.json)
- [Local readiness checkpoint checks](verification/VER-QA-010-CHECKPOINT.md)
- [Account-bound receiving views](verification/VER-QA-011-RECEIVING.md) and [latest mobile source/results](verification/QA-011-results.json)
- [Physical local notification delivery/permission acceptance](verification/VER-QA-013-ANDROID-NOTIFICATIONS.md) and [source delta/results](verification/QA-013-results.json)
- [Android candidate publication contract](releases/README.md)
- [Android background reminder contract and setup](project/BACKGROUND_REMINDERS.md)
- [Tablet test automation (USB and paired Wi-Fi)](project/USB_TESTING.md)
- [Azure migration preparation and required access](project/AZURE_MIGRATION.md)
- [Azure App Service worker deployment and cost review](project/AZURE_DEPLOYMENT.md)
- [Historical records and former manual](archive/INDEX.md)

## Feature and implementation plans

| Plan | Owner role |
|---|---|
| [ledger-and-sync](plans/ledger-and-sync.md) | Data/sync agent |
| [groups-and-expenses](plans/groups-and-expenses.md) | Ledger/UI agent |
| [payment-methods-and-qr](plans/payment-methods-and-qr.md) | Payments agent |
| [settlement-and-receipts](plans/settlement-and-receipts.md) | Payments/backend agent |
| [security-and-privacy](plans/security-and-privacy.md) | Security agent |
| [onboarding-and-auth](plans/onboarding-and-auth.md) | Identity agent |
| [home-and-notifications](plans/home-and-notifications.md) | Mobile agent |
| [profile-and-connections](plans/profile-and-connections.md) | Profile agent |
| [android-and-release](plans/android-and-release.md) | Platform/release agent |
| [missing-capabilities](plans/missing-capabilities.md) | Feature agent |

## Shared memory

[Task records](progress/tasks/), [status projection](progress/STATUS.md), [feature template](templates/feature-plan.md), [task template](templates/task-record.md), [verification template](templates/verification-record.md). Task metadata is authoritative; status is generated. Root defines procedure, accepted decisions define intent, task/evidence records establish implementation truth.

Run `node scripts/check-project-memory.cjs --write` after task metadata changes, then `node scripts/check-project-memory.cjs --base <task-base-commit>` before handoff. CI enforces record consistency and change coverage; review establishes whether evidence supports claims.

## Android and migration acceptance 2026-11-14T14:20:41.074+08:00

- [Actual Android 16KB encrypted storage and session acceptance](verification/VER-QA-014-16KB.md)
- [Private production signing and Android staging upgrade rehearsal](verification/VER-QA-015-SIGNING.md)
- [Actual notification cold launches after process death and emulator reboot](verification/VER-QA-016-LIFECYCLE.md)
- [Approved Azure friendship security patch and live consent acceptance](verification/VER-QA-017-DEPLOYED.md)
- [Firebase sign-in and project-quota setup blocker](verification/VER-QA-018-FIREBASE.md)
- [Combined sanitized source/results](verification/QA-018-results.json)

- [Release-signed encrypted storage upgrade](verification/VER-QA-019-SIGNED-STORAGE.md) and [source/results](verification/QA-019-results.json).

- [Clean signed physical tablet live-testing installation](verification/VER-QA-021-CLEAN-TABLET.md) and [exact artifact/results](verification/QA-021-results.json).

- [Working Google OAuth, callback repair and physical Android regressions](verification/VER-QA-022-GOOGLE.md), with [sanitized source/results](verification/QA-022-results.json).

- [Free Firebase keyless Android setup plan](plans/firebase-keyless-android.md).

- [Google-only welcome/introduction plan](plans/google-entry-introduction.md), [artwork/prompts](assets/google-welcome-prompts.md) and [tablet/server verification](verification/VER-QA-025-GOOGLE-ENTRY.md).

- [Firebase keyless setup and actual Android FCM delivery](verification/VER-QA-018-KEYLESS.md), with [sanitized results](verification/QA-018-keyless-results.json).

- [App-wide warm UI plan](plans/consistent-warm-ui.md), [current design contract](project/DESIGN.md) and [reusable Tabby design skill](../.agents/skills/tabby-design/SKILL.md).

- [Consistent warm UI and reusable skill verification](verification/VER-QA-026-WARM-UI.md), [source/results](verification/QA-026-results.json).

- [Minimal daily-debt Home and rounded choices](plans/minimal-daily-debts-home.md).

- [Notification tap and ascending ledger cursor repair](verification/VER-QA-027-NOTIFICATION-TAP.md), [sanitized results](verification/QA-027-results.json).

- [Minimal Home/appearance verification](verification/VER-QA-028-DAILY-HOME.md), [source/results](verification/QA-028-results.json).

- [Visible feedback and balanced navigation audit](plans/ui-feedback-audit.md), [task QA-029](progress/tasks/QA-029.md).

- [Visible sheet feedback and lower-right Add verification](verification/VER-QA-029-VISIBLE-FEEDBACK.md).

- [Native warm/cold notification intent acceptance](verification/VER-QA-027-NATIVE-INTENTS.md), [sanitized results](verification/QA-027-native-results.json).

- [Full-screen forms and edge-to-edge compact sheets](plans/fullscreen-forms-and-edge-sheets.md), [QA-030](progress/tasks/QA-030.md).

- [Exact signed normal17 native16KB/physical ARM64 acceptance](verification/VER-QA-014-CANDIDATE17.md), [results](verification/QA-014-CANDIDATE17-results.json).

- [Full-screen form and edge-to-edge sheet verification](verification/VER-QA-030-FORM-PRESENTATION.md).

- [Situation mascot animation plan](plans/situation-mascot-animation.md), [QA-031](progress/tasks/QA-031.md).

- [Create Tab/custom debt design](plans/create-tab-custom-debts-design.md) and [implementation](plans/create-tab-custom-debts.md): [QA-032](progress/tasks/QA-032.md).

- [Situation mascot artwork/animation contract](assets/situation-mascot-artwork.md).

- [Situation mascot animation verification](verification/VER-QA-031-SITUATION-MASCOTS.md).

- [Articulated mascot frames and prompts](assets/articulated-mascot-frames.md), [implementation plan](plans/articulated-mascot-frames.md), [verification](verification/VER-QA-033-ARTICULATED-MASCOTS.md).

- [Create Tab and custom amounts — user summary](plans/expense-entry-update-summary.md), [Android22 source](verification/QA-032-v22-source-manifest.json).

- [iOS sideload and Android parity](project/IOS_SIDELOAD.md), [unsigned IPA evidence](verification/VER-QA-034-IOS-PARITY.md).
