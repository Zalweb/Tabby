# Remaining mobile readiness issues

```json verification-metadata
{
  "id": "REMAINING_ISSUES",
  "task_ids": [
    "QA-003",
    "QA-004",
    "QA-005",
    "QA-006",
    "QA-007",
    "QA-008",
    "QA-009",
    "QA-010",
    "QA-011",
    "QA-012",
    "QA-013"
  ],
  "timestamp": "2026-11-14T03:16:51.639+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Mobile audit handoff. Local implementation/regression passes are separate from required external acceptance.",
  "commands": [
    "See VER-QA-003-MOBILE.md and linked owning task records",
    "See VER-QA-005-SOCIAL.md for latest client-only verification",
    "See VER-QA-006-FRIENDSHIP.md for latest SQL authorization/fresh-upgrade evidence"
  ],
  "checks": [
    {
      "category": "remaining-issues-inventory",
      "outcome": "passed"
    },
    {
      "category": "production-readiness",
      "outcome": "unverified"
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

### Superseding tablet transport observation — 2026-11-14T00:48:44.438+08:00

[QA-009](VER-QA-009-ANDROID-TRANSPORT.md): the newly observed TLS advertisement actively refuses connection10061, with zero attached devices. Native preflight/install/smoke/matrix did not run; QA-009 is blocked pending an awake/listening already paired tablet. No device mutation occurred. [QA-008712-test/analysis/debug evidence](VER-QA-008-AUTH.md) remains current; independent source review and the broader goal continue. Production NO-GO remains.

### Superseding auth completion review — 2026-11-14T00:45:38.628+08:00

[QA-008](VER-QA-008-AUTH.md) repairs obsolete login/signup completions restoring auth/profile flags, disposed signup completion and unhandled optional preference writes. Public SDK event acknowledgment preserves legitimate completion. Final15 focused/712 full Flutter, clean analysis and isolated Android debug packaging62.4s pass; [latest source/results](QA-008-results.json) identify current mobile source. Backend/native/tooling remain QA-007 scope. A new paired-tablet TLS advertisement makes native preflight actionable; identity/device execution is not yet established. Production remains NO-GO with provider/iOS/independent review/exact signed release gates open.

### Superseding pair concurrency review — 2026-11-13T18:57:37.739+08:00

[QA-007](VER-QA-007-SOCIAL-CONCURRENCY.md) repairs duplicate opposing pending requests and same-direction duplicate-key failures with canonical-pair transaction serialization. Eight native races across50→52,51→52,fresh52 and standalone snapshot pass, retaining consent/private-access regressions. Full local API fresh52/pending34 passes. [Latest source/results](QA-007-results.json) supersede only local SQL inputs; mobile source remains unchanged. Production remains NO-GO, both local security/social migrations are unapplied, and native/platform/provider/independent review/signed release gates stay open.

### Superseding friendship authorization review — 2026-11-13T18:49:13.170+08:00

[QA-006](VER-QA-006-FRIENDSHIP.md) reproduces a local source consent bypass: direct accepted-friendship INSERT grants private profile/receiving/avatar access. An additive RPC-only insertion migration repairs it, plus declined-request resend42702 and acceptance-notification42703 failures. Executable snapshot separators/trigger are synchronized. Fresh51-migration,50→51 upgrade and standalone snapshot authorization tests pass; full local PostgREST fresh51/pending33 and independent-session financial subset pass. [Latest source/results](QA-006-results.json) record final hashes. QA-005697 client tests/clean analysis/debug build apply to unchanged mobile source. Production remains NO-GO: this security repair is not deployed, effective deployed policies need authorized review, existing rows remain untouched, and native/platform/provider/independent review/release gates remain open. No production exposure or remediation is inferred from local source alone.

### Superseding social review — 2026-11-13T18:36:38.648+08:00

[QA-005 evidence](VER-QA-005-SOCIAL.md) records repaired old-session friend results, validated decision acknowledgments, account-bound friend sheets, edited-ID identity mismatches and opposing pending response taps. Final full Flutter697/697, clean analysis and isolated Android debug build19.9s pass. [Current source/results](QA-005-results.json) identify this newer dirty source. SDK dispatch token-switching was investigated and not reproduced; no transport pinning claim. Backend contracts are unchanged. Full source review remains active; real native/provider/independent review and exact signed release gates remain open. Production remains NO-GO.

### Superseding local progress — 2026-11-13T18:07:00+08:00

[QA-004](VER-QA-004-MOBILE.md) repairs additional payment/read-order, account-bound modal and large-text layout defects, with670 full Flutter tests and clean analysis. Current ADB device/mDNS inventories remain empty. The release, iOS/device, real platform/provider, independent review and exact signed-candidate gates below remain open. This audit does not claim that every application logic path has been exhaustively reviewed; continue the active source review while arranging those environments. No remote mutation/deployment occurred.

As of2026-11-13T16:30:00+08:00 the current dirty source is **NO-GO for production**. Local repair work and available checks passed. The following gates require environment/input, independent review or separate operational authorization; they are not declarations that existing implemented features are absent. Priority P1 is release/verification impact, not proof that the current deployed service is compromised. Authoritative states remain in linked task records.

| Priority / issue | Impact and owner | Actual blocker / required environment or authorization | Release effect / precise next action |
|---|---|---|---|
| P1 — Review/integrate current dirty source | [QA-003](../progress/tasks/QA-003.md), integration owner; QA-001/REL-001. Local fixes are not independently reviewed or integrated. | Preserved AZ-001/QA-002 and mobile edits share this dirty branch; no independent review exists. No authorization is needed for local review, but independent reviewer availability is required. | Blocks completion and clean candidate. Review the [source manifest](QA-003-source-manifest.json), focused upload/native/test diff and evidence; integrate only owned/reviewed changes. Do not erase or commit unrelated work to manufacture a clean tree. |
| P1 — Real immutable-upload replay | [PAY-002](../progress/tasks/PAY-002.md), [PAY-003](../progress/tasks/PAY-003.md), QA-003; affected receipts/proofs can otherwise stall queue reconciliation. | Local fixture repair passes; the combined real Storage+financial response-loss boundary has not run. Needs explicitly authorized dedicated synthetic accounts in an appropriate test backend; copied Azure records are not disposable. | Blocks these M1 acceptance gates. Upload, commit the linked expense/payment while dropping its response, replay with the same operation/bytes; prove one financial row, preserved object and successful queue acknowledgment. Verify changed bytes, unauthorized read, logout/relogin and account-switch denial on Android/iOS. |
| P1 — Full Supabase authorization/platform acceptance | [QA-001](../progress/tasks/QA-001.md), SEC-002/004/005, QR/PAY/LED tasks. | Current public-schema/PostgREST tests use injected Auth/Storage tables and self-issued JWTs. Historical Azure Auth/Storage26-check results are narrower than full candidate acceptance. No full local Supabase runtime (Docker/Podman absent). Remote test mutation needs environment/account authorization. | Blocks M1 required live/backend gates. Run actual issued-token positive/negative RLS/RPC/Storage/proof revision and signed-URL expiry tests, real account switching, deletion/session/media guards and cross-user/lifecycle Realtime. Record exact deployed migration inventory and tested candidate. |
| P1 — Physical Android lifecycle/UX coverage | [QA-001](../progress/tasks/QA-001.md), AND-001..004, SEC-001/003, HOME-003/004; QA-002 runner retained. | Current ADB device and mDNS lists are empty; default AVD list empty. Historical paired-Wi-Fi tablet passes used4096-byte pages and mostly fixtures/scheduling probes. | Blocks current android-device acceptance. Reconnect an already authorized tablet; use USB preflight or explicitly authorized advertised private TLS Wi-Fi with hardware/package rechecks. Run isolated smoke/matrix, then real cold/resume/PIN/biometric, permission denial, picker interruption, back/large-text/accessibility/low-memory and actual notification delivery/tap journeys. Preserve production package/data. |
| P1 — iOS native notification/runtime acceptance | [QA-003](../progress/tasks/QA-003.md); affects foreground local alerts and tap forwarding. | Delegate repair has static regression only; Windows has no Xcode or iPhone runtime. Needs Mac/Xcode and supported iPhone/simulator plus test credentials where applicable. | Blocks iOS distribution, not Android solely because iOS is unavailable. Build existing native source, test notification allow/deny, foreground/background/cold taps while locked, key/database reopen, Face ID/PIN, picker, recovery/Google callbacks and account isolation. Record exact iOS artifact/OS. |
| P1 — Google/recovery/provider email journeys | [QA-002](../progress/tasks/QA-002.md), AUTH-002..005, PRO-001 and [REL-001](../progress/tasks/REL-001.md). | Native IDs/copied Google settings are configuration only. Azure own-recipient SMTP was user-confirmed historically; Resend test sender cannot serve arbitrary users. Provider/domain ownership and callback/client certificate setup plus authorized fixture delivery needed. | Blocks relevant candidate OAuth/recovery and destination cutover. Verify production-capable sender domain, valid/expired/reused link handling, native Google/callback flow and signout/relogin on each platform. Do not enable signup or send user mail from this audit. |
| P1 — Remote background reminder delivery | [HOME-004](../progress/tasks/HOME-004.md), QA-001/QA-002. Acceptance/inbox writes must not imply device receipt. | Historical Azure record says Firebase credentials unconfigured and schedulers disabled. Current worker mocks/GET probes do not establish FCM delivery. Needs provider configuration and explicitly authorized dedicated device/account tests. | Blocks required background-delivery acceptance. Verify provider acceptance versus actual delivery/taps, foreground/background/process-death/force-stop/reboot separately, denied notifications and obsolete bindings. Do not enable workers/schedulers merely to pass a test. |
| P1 — Signed artifact, real upgrade,16KB runtime | [REL-001](../progress/tasks/REL-001.md), AND-005 and QA-001. | Only isolated debug APK exists; dirty source, no reviewed signing identity/clean candidate, no prior-release upgrade or16KB device. Publication excluded by current prompt. | Blocks Android production GO. After review and prerequisite acceptance, build exact clean release-signed APK in protected CI; verify digest/cert/package/version/ZIP+ELF, real data-preserving upgrade from prior release, OAuth and16KB runtime. Record all ten release categories against that exact artifact. Public release still requires actual session signoff. |
| P1 — Azure operational cutover gates | [QA-002](../progress/tasks/QA-002.md), integration/operations owner; DEC-012. | Restored copied data/source remain active separately. Historical off-VM recovery depends on Windows-user DPAPI; owner-managed key retention/scheduled backups, fresh cold bootstrap, production sender, Google/FCM and broader Realtime are not accepted. Current GET probes only show health/denial. | Blocks destination cutover. Under separately authorized operations, establish owner recovery retention and scheduled restore drill, cold-bootstrap acceptance, provider journeys, final consistent write freeze/delta reconciliation and reviewed rollback/rollout. Retain original backend/history. Respect USD100 total student credit and enabled spending limit; no cloud changes/spending/billing conversion authorized here. |
| P2 — iOS remote push and same-phone QR export are unwired | QA-003 platform scope; [HOME-004](../progress/tasks/HOME-004.md), [QR-006](../progress/tasks/QR-006.md). | Current BackgroundReminderService and ReceivingQrExport support Android only. iOS local notifications and QR display/upload exist. iOS APNs/FCM credentials/entitlements and native share/save acceptance are not supplied; current accepted tasks specify Android implementation. | Does not independently block Android M1; blocks claiming iOS parity in these flows. Agree the intended iOS release capability and native contracts, then implement/review/test required ports using platform credentials. Keep unavailable controls truthful in the interim. |
| P2 — Hidden M2 acceptance | [CAP-002](../progress/tasks/CAP-002.md), [CAP-003](../progress/tasks/CAP-003.md), [CAP-004](../progress/tasks/CAP-004.md), [CAP-005](../progress/tasks/CAP-005.md). | Source and local tests exist, client/server rollout remains disabled; M1 dependencies, real staging/device consent/scheduler/rollback and review remain incomplete. | Hidden optional M2 does not block otherwise eligible M1. Stabilize/accept M1 first, then dedicated feature acceptance with actual parties/provider/device; never enable flags based on local counts. |
| P3 — Toolchain/dependency maintenance evidence | Platform/release owner under [QA-003](../progress/tasks/QA-003.md) and AND-004/005. | Android build succeeds with Java native-access and package_info_plus Kotlin-plugin future-compatibility warnings. No general current dependency vulnerability-database clearance was performed. | Not a reproduced release failure in this toolchain. Before future SDK changes, evaluate compatible targeted package fixes and current advisory results, retain signing/security gates and rerun relevant mobile checks. No blanket/force upgrade. |

## Evidence

[Current verification](VER-QA-003-MOBILE.md), [feature inventory and gate decision](PRODUCTION_READINESS_REPORT.md), [repaired issues](BUG_FIX_CHANGELOG.md), [sanitized local results](QA-003-local-results.json). Historical checkpoints are retained in [Azure restore](VER-QA-002-AZURE-RESTORE.md), [paired tablet](VER-QA-002-WIFI-TABLET.md) and their owning tasks. They supersede earlier missing-restore/device statements only for their exact dated scenarios.

## Limits and next action

No currently reproduced local test failure remains after the repairs. Remaining acceptance requires the environments, independent reviewer, credentials/ownership or operational authorization listed above. Proceed with local review while arranging the Android/iOS and dedicated backend test environments; do not repeat empty-device or blocked provider attempts without new evidence. No production publication, cutover, real-data repair, resource change, user messaging or M2/signup/scheduler activation occurred.

## 2026-11-14T14:20:41.074+08:00 — Superseding remaining gates

The generic16KB-runtime and missing-production-key gaps now have bounded local acceptance, and the two pending friendship security migrations are applied on Azure migration destination only. Keep remaining gates open: designate an unused nonbilled Google project or increase quota; register/configure Firebase and prove real FCM delivery/lifecycle; verify Google/SMTP/Storage/providers and complete Android M1 journeys; signed financial queued-data/legacy-debug transition; exact final candidate and ARM64 runtime; complete migration/cutover/recovery restore and independent review. New-key v5→v6 preserved synthetic Auth/onboarding on16KB x86_64 only. Closed/reboot alarm payload tests are local alarms, not FCM or locked authenticated routing. iOS deferred. [Actual Android 16KB encrypted storage and session acceptance](VER-QA-014-16KB.md), [Private production signing and Android staging upgrade rehearsal](VER-QA-015-SIGNING.md), [Actual notification cold launches after process death and emulator reboot](VER-QA-016-LIFECYCLE.md), [Approved Azure friendship security patch and live consent acceptance](VER-QA-017-DEPLOYED.md), [Firebase sign-in and project-quota setup blocker](VER-QA-018-FIREBASE.md). No production-ready/publication claim.

## 2026-11-14T14:33:57.367+08:00 — Signed financial storage upgrade rehearsal

Actual release/AOT v7 seed and same-production-key v8 upgrade verified the production default encrypted ledger factory, all10000 synthetic history entries/IDs/order/centavos, an unchanged durable operation ID/payload, secure draft and PIN, same secure encryption key and owner isolation. All runtime checks are explicit exceptions rather than release-disabled assertions. A normal-main v9 restoration APK was built and validated before any fixture installation, then installed/launched in finally. Every install rechecked qemu1/x86_64/16384-byte pages, exact APK bytes/certificate, version and unchanged Android appId. Starting v6 APK bytes were pulled and matched the exact known private baseline before replacing it. See [release-signed encrypted storage upgrade](VER-QA-019-SIGNED-STORAGE.md). This is a new-key synthetic release-signed storage upgrade rehearsal, not an upgrade from either old debug-signed APK, backend command replay, real financial operation, full app/candidate acceptance or ARM64 runtime. Firebase project choice/quota, provider/live journeys and independent integration review remain open. The personal tablet was never targeted; iOS deferred. The earlier generic signed-financial-storage rehearsal gap now has bounded new-key emulator acceptance; legacy/debug transition and final exact candidate gates remain open.

## 2026-11-14T16:06:03.377+08:00 — Clean physical live-testing installation

User-authorized normal release v1.0.4+10 is now installed fresh on the Lenovo tablet, signed out at onboarding. Exact installed bytes match SHA256 9b5ccd7554c90c9248ef65dcc2e50e16722e075609746be9a2e285c31f540751. APK scan found no selected fixture credentials, synthetic seed markers or packaged ledger database. Temporary test app/data removed after five native smoke cases and real SDK Auth/RLS/Realtime pass;76 Node checks, analysis, four anonymous probes and same-APK16KB startup pass. [Evidence](VER-QA-021-CLEAN-TABLET.md), [results](QA-021-results.json). User will use an existing account; its cloud history is retained. Signup disabled; Google/FCM/providers/final synchronization/cutover/full journeys/review remain open. This private acceptance install is not production readiness or public publication.

## 2026-11-17T07:04:59.293Z — Superseding Android/Google status

The reported Google browser sign-in failure is repaired and has actual owner Home/new-server-session acceptance; do not continue listing it as a current generic provider blocker. [QA-022](VER-QA-022-GOOGLE.md) is implemented with independent integration review pending. Normal same-key12 is installed and verified privately; a clean final release candidate is still required. Earlier no-device/no-signing/no16KB-runtime statements are historical and superseded only to the bounded extent recorded in QA-014 through QA-024.

| Priority / owner | Remaining impact and exact next action | Release effect |
|---|---|---|
| P1 / QA-018, HOME-004 / Codex root + project owner | Firebase CLI inventory refreshed: no named Tabby project; previously reviewed existing project has billing off. Owner must choose unused existing project or resolve quota. Then register Android/signature, configure sender privately and verify real closed/background/rotation/logout/tap delivery. | Remote push remains unavailable; local alarms are separate evidence. |
| P1 / QA-002, AZ-001 / migration owner | Verify production-capable email delivery, final consistent delta/source freeze, restore/rollback and client rollout against approved destination. Current Google repair does not authorize global cutover. | Backend production cutover remains open. |
| P1 / QA-001 / integration owner | Complete remaining actual financial/Storage/lifecycle journeys using explicitly approved synthetic accounts; preserve migrated originals and owner data. Current local/physical fixtures do not prove every platform flow. | Full M1 acceptance incomplete. |
| P1 / REL-001 / reviewer + release owner | Independently review integrated changes; produce exact clean signed candidate and verify every required category against its digest/certificate/version. | No public release or production GO. |
| Deferred / native iOS owner | Appropriate Mac/device runtime later, per current Android-only instruction. Preserve shared source. | No iOS readiness claim. |

## 2026-11-17T07:51:50.737Z — Firebase setup blocker replaced by end-to-end queue acceptance

Free Firebase now configured in the owner-selected existing project; no billing or downloadable key. Exact-VM federation/deployed runtime authorization and actual isolated Android background/process-death FCM delivery pass. Normal13 has verified public Firebase identifiers. The previous project-selection/no-config blocker is resolved. [QA-018](VER-QA-018-KEYLESS.md) stays in_progress: real Auth-backed registration/reminder queue/worker/tap, full account/token lifecycle and gated scheduler activation still need acceptance. Direct native fixtures do not prove every backend journey. Production NO-GO and independent review/cutover/exact-candidate gates remain.


## Notification ledger cursor checkpoint — 2026-11-17T09:42:46.633Z

Real spare-Google notification testing exposed Tab not found. Initial route-readiness repair failed physically; isolated runtime then proved Invalid tab cursor because the SDK defaulted descending. Production headers now explicitly ascend, and notification navigation awaits a scoped exact target. Actual SDK cursor regression,24 focused tests,754-test owned snapshot/full analysis and819-test integrated UI run pass. Signed normal15 contains exact functional source hashes and is installed in place, retaining data/session. Actual queue/group native posting is proved; corrected final tap, further lifecycle and independent review remain open. Synthetic sender access is retired; no existing financial history changed or scheduler/public release activated. [Current evidence](VER-QA-027-NOTIFICATION-TAP.md).


## Native reminder handoff checkpoint — 2026-11-17T10:31:22.718Z

The actual router error and closed-app Home fallback are now corrected by explicit Android link ownership plus a Dart-listener handshake before destructive intent consumption. Final real warm/cold drawer taps show the correct existing spare-account group/PHP1.00; native4 regressions pass. Signed normal16 is installed in place with exact digest02dd7199462e1ffc1b24372aa1e95c8b76a8b893475899982220cd3c9e240f8f, preserving owner data/session and reserved test packages. Final live financial integrity passes, sender remains retired and pending jobs0. This supersedes older pending-tap/main15 notes. Independent review/clean final candidate, remaining lifecycle/backend/cutover and exact16KB runtime remain open; no scheduler/public release. [Current evidence](VER-QA-027-NATIVE-INTENTS.md).


## Signed normal17 compatibility checkpoint — 2026-11-17T13:29:14.425Z

Same exact signed APK 626b8084ac4894bdebaa8d9c05e3d385f291ead28a62ba9eafa114bf78bbe3c7 now runs natively on16KB x86_64 emulator and4KB ARM64 tablet, with installed bytes/signature/static/runtime checks and data-preserving upgrade. The failed ARM64-only normal16 emulator observation is retained as architecture mismatch.17 reuses frozen accepted16 UI/native source; concurrent QA-030 form changes excluded and preserved. Current broader review/clean-candidate/backend/cutover/scheduler gates remain open. [Evidence](VER-QA-014-CANDIDATE17.md).
