# Current project progress

Generated from task metadata by `node scripts/check-project-memory.cjs --write`. Do not edit this projection manually. Ownership, evidence and handoff details live in task records.

## Milestones

| Milestone | Implemented or later / total | Verified or complete / total | Complete / total |
|---|---|---|---|
| M0 | 1 / 1 | 1 / 1 | 1 / 1 |
| M1 | 68 / 69 | 1 / 69 | 1 / 69 |
| M2 | 4 / 4 | 0 / 4 | 0 / 4 |
| M3 | 8 / 14 | 0 / 14 | 0 / 14 |

Implementation coverage counts source work; complete additionally requires every acceptance, review and integration gate. Local fixtures never establish live backend or real-device acceptance.

## M1 acceptance review

Local review recorded for 47 / 69 tasks. Open checks below remain unverified until their required environment is actually tested.

| Open check | Incomplete tasks requiring it |
|---|---|
| 16kb-device | 1 |
| analysis | 17 |
| android-device | 27 |
| android-lifecycle | 1 |
| animation-lifecycle | 2 |
| backend-authorization | 10 |
| backend-integration | 17 |
| deployed-catalog | 1 |
| feedback-visibility | 1 |
| google-registration | 1 |
| integration | 22 |
| integration-review | 68 |
| ios-device | 2 |
| live-backend | 37 |
| live-notification-tap | 1 |
| migration-source | 1 |
| presentation-geometry | 1 |
| release-artifact | 6 |
| skill-validation | 1 |
| upgrade | 1 |
| visual-consistency | 2 |

M3 candidate/device/deployment verification remains a release gate even before a candidate task is claimed. No remediation is inferred from a baseline test count.

## Tasks, owners and next actions

| Task | Milestone | Priority | State | Owner | Dependencies / next action |
|---|---|---|---|---|---|
| [AND-001](tasks/AND-001.md) � Android scheduled notification integration is incomplete | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [AND-002](tasks/AND-002.md) � Secure-storage backup rules are absent | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [AND-003](tasks/AND-003.md) � Picker recovery and draft/back protection are missing | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [AND-004](tasks/AND-004.md) � History loading and cache rewriting will scale poorly | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [AND-005](tasks/AND-005.md) � Automatic release can publish a debug-signed APK | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [AUTH-001](tasks/AUTH-001.md) � Startup errors can block authentication initialization | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [AUTH-002](tasks/AUTH-002.md) � Password recovery and confirmation assistance are missing | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [AUTH-003](tasks/AUTH-003.md) � Profile completion ignores failed method saves | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [AUTH-004](tasks/AUTH-004.md) � Phone validation and default wallet assumptions are weak | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [AUTH-005](tasks/AUTH-005.md) � Onboarding accessibility and back behavior need validation | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [AZ-001](tasks/AZ-001.md) � Prepare Supabase workers for Azure App Service | M3 | P1 | in_progress | Codex root | INT-001; read task handoff |
| [CAP-001](tasks/CAP-001.md) � Documented ledger capabilities are absent | M1 | P2 | implemented | Codex desktop privacy | LED-003, PAY-001; read task handoff |
| [CAP-002](tasks/CAP-002.md) � Custom splits and tax/service charges | M2 | P2 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [CAP-003](tasks/CAP-003.md) � Recurring obligations | M2 | P2 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [CAP-004](tasks/CAP-004.md) � Explicit contact claiming | M2 | P2 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [CAP-005](tasks/CAP-005.md) � Acknowledgment, proposals and disputes | M2 | P2 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [CAP-006](tasks/CAP-006.md) � Audited corrections and cancellation | M1 | P2 | implemented | Codex desktop corrections | LED-003, PAY-001; read task handoff |
| [DOC-001](tasks/DOC-001.md) � Establish modular project memory and audit implementation backlog | M0 | P1 | complete | Codex root | none; see verification |
| [GRP-001](tasks/GRP-001.md) � Group payments change uninvolved balances | M1 | P1 | implemented | Codex root | LED-001, LED-003; read task handoff |
| [GRP-002](tasks/GRP-002.md) � Group shares and payer selection are incomplete | M1 | P1 | implemented | Codex root | LED-001, LED-003; read task handoff |
| [GRP-003](tasks/GRP-003.md) � Group settlement treats a group as a person | M1 | P1 | implemented | Codex root | LED-001, LED-003; read task handoff |
| [GRP-004](tasks/GRP-004.md) � Group creation is partially committed | M1 | P2 | implemented | Codex root | LED-001, LED-003; read task handoff |
| [GRP-005](tasks/GRP-005.md) � Malformed currency is accepted or throws without feedback | M1 | P2 | implemented | Codex root | LED-001, LED-003; read task handoff |
| [HOME-001](tasks/HOME-001.md) � Dashboard labels and monthly filter misrepresent data | M1 | P2 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [HOME-002](tasks/HOME-002.md) � Settled reminders return after refresh | M1 | P1 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [HOME-003](tasks/HOME-003.md) � Notification preferences and permissions are disconnected | M1 | P1 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [HOME-004](tasks/HOME-004.md) � Reminder sent state and closed-app delivery are unreliable | M1 | P2 | implemented | Codex root | LED-003, PAY-001; read task handoff |
| [INT-001](tasks/INT-001.md) � Freeze shared contracts and assign integration ownership | M1 | P1 | complete | Codex root | DOC-001; see verification |
| [LED-001](tasks/LED-001.md) � Different people merge by display name | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [LED-002](tasks/LED-002.md) � Distinct same-price expenses disappear | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [LED-003](tasks/LED-003.md) � Retries can duplicate server writes | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [LED-004](tasks/LED-004.md) � Failed operations can continuously retry | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [LED-005](tasks/LED-005.md) � Contact payer and settlement paths lose synchronization | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [LED-006](tasks/LED-006.md) � Sync diagnostics overstate success | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [PAY-001](tasks/PAY-001.md) � Confirm Payment inserts a separate payment | M1 | P1 | implemented | Codex root | LED-003, GRP-001; read task handoff |
| [PAY-002](tasks/PAY-002.md) � Submit Payment Proof does not attach payment proof | M1 | P1 | implemented | Codex root | LED-003, GRP-001; read task handoff |
| [PAY-003](tasks/PAY-003.md) � Receipt status claims verification without evidence | M1 | P2 | implemented | Codex root | LED-003, GRP-001; read task handoff |
| [PAY-004](tasks/PAY-004.md) � Concurrent confirmations may overpay | M1 | P1 | implemented | Codex root | LED-003, GRP-001; read task handoff |
| [PRO-001](tasks/PRO-001.md) � Profile writes can report false success | M1 | P2 | implemented | Codex root | QR-003; read task handoff |
| [PRO-002](tasks/PRO-002.md) � Avatar camera/gallery choices are placeholders | M1 | P2 | implemented | Codex root | QR-003; read task handoff |
| [PRO-003](tasks/PRO-003.md) � Friend and group actions overstate persistence/deletion | M1 | P2 | implemented | Codex root | QR-003; read task handoff |
| [PRO-004](tasks/PRO-004.md) � Preferences are partially implemented | M1 | P3 | implemented | Codex root | QR-003; read task handoff |
| [QA-001](tasks/QA-001.md) � Verify integrated Android core and migration upgrade | M3 | P1 | in_progress | Codex root | AND-001, AND-002, AND-003, AND-004, AND-005, AUTH-001, AUTH-002, AUTH-003, AUTH-004, AUTH-005, CAP-001, CAP-006, GRP-001, GRP-002, GRP-003, GRP-004, GRP-005, HOME-001, HOME-002, HOME-003, HOME-004, INT-001, LED-001, LED-002, LED-003, LED-004, LED-005, LED-006, PAY-001, PAY-002, PAY-003, PAY-004, PRO-001, PRO-002, PRO-003, PRO-004, QR-001, QR-002, QR-003, QR-004, QR-005, QR-006, SEC-001, SEC-002, SEC-003, SEC-004, SEC-005; read task handoff |
| [QA-002](tasks/QA-002.md) � Tablet automation and Azure backend migration | M3 | P1 | in_progress | Codex root | INT-001; read task handoff |
| [QA-003](tasks/QA-003.md) � Android and iOS production-readiness audit and safe repairs | M3 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-004](tasks/QA-004.md) � Scope asynchronous payment actions to their session and route | M3 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-005](tasks/QA-005.md) � Account-bound friend requests and truthful social acknowledgments | M3 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-006](tasks/QA-006.md) � Enforce friendship consent at the database write boundary | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-007](tasks/QA-007.md) � Serialize friend-request creation across devices and directions | M1 | P1 | implemented | Codex root | INT-001, QA-006; read task handoff |
| [QA-008](tasks/QA-008.md) � Session-bound authentication completion | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-009](tasks/QA-009.md) � Recheck current Android source on the paired physical tablet | M1 | P1 | implemented | Codex root | INT-001, QA-002, QA-008; read task handoff |
| [QA-010](tasks/QA-010.md) � Review and commit the readiness checkpoint | M3 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-011](tasks/QA-011.md) � Account-bound receiving methods and QR views | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-012](tasks/QA-012.md) � Android execution of current session regressions | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-013](tasks/QA-013.md) � Physical Android local notification delivery acceptance | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-014](tasks/QA-014.md) � Android 16KB runtime and native storage acceptance | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-015](tasks/QA-015.md) � Production signing identity and Android release preparation | M3 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-016](tasks/QA-016.md) � Android closed-process and reboot notification cold launch | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-017](tasks/QA-017.md) � Review and apply pending Azure migration security patch | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-018](tasks/QA-018.md) � Firebase Spark Android push setup | M3 | P1 | in_progress | Codex root | INT-001; read task handoff |
| [QA-019](tasks/QA-019.md) � Release-signed encrypted financial cache upgrade rehearsal | M3 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-020](tasks/QA-020.md) � Remove old Tabby installations from the personal tablet | M3 | P2 | implemented | Codex root | INT-001; read task handoff |
| [QA-021](tasks/QA-021.md) � Clean release build and personal tablet live acceptance installation | M3 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-022](tasks/QA-022.md) � Repair Google browser OAuth handoff and missing Azure callback | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [QA-023](tasks/QA-023.md) � Implement supplied mascot blink, generate launcher icon and update tablet | M1 | P2 | implemented | Codex root | INT-001, PRO-004, QA-021; read task handoff |
| [QA-024](tasks/QA-024.md) � Enhance login page with a larger mascot and responsive sign-in card | M1 | P2 | implemented | Codex root | INT-001, QA-023; read task handoff |
| [QA-025](tasks/QA-025.md) � Google-only sign-in and clean post-authentication mascot introduction | M1 | P1 | in_progress | Codex root | INT-001, QA-022, QA-024; read task handoff |
| [QA-026](tasks/QA-026.md) � Apply the login/introduction warm design throughout Tabby and provide a reusable skill | M1 | P1 | implemented | Codex root | INT-001, QA-025; read task handoff |
| [QA-027](tasks/QA-027.md) � Repair real Android notification tap opening an unloaded tab | M1 | P1 | implemented | Codex root | INT-001, QA-018; read task handoff |
| [QA-028](tasks/QA-028.md) � Redesign mascot-led Home and simplify real daily-debt controls | M1 | P1 | implemented | Codex root | INT-001, QA-026; read task handoff |
| [QA-029](tasks/QA-029.md) � Audit covered errors and notifications; balance navigation with lower-right Add | M1 | P1 | implemented | Codex root | INT-001, QA-028; read task handoff |
| [QA-030](tasks/QA-030.md) � Full-screen entry forms and full-width compact sheets | M1 | P2 | implemented | Codex root | INT-001, QA-029; read task handoff |
| [QA-031](tasks/QA-031.md) � Animate supplied situation mascots with lifecycle and reduced-motion support | M1 | P2 | implemented | Codex root | INT-001, QA-023, QA-030; read task handoff |
| [QA-032](tasks/QA-032.md) � Recognize shared tabs, warn about duplicate expenses and support custom amounts | M1 | P1 | implemented | Codex root expense-entry session | INT-001, LED-003, PAY-001, CAP-002; read task handoff |
| [QA-033](tasks/QA-033.md) � Add matching eye, tail and paw animation frames to situation mascots | M1 | P2 | implemented | Codex root mascot | INT-001, QA-031; read task handoff |
| [QA-034](tasks/QA-034.md) � Review Android/iOS feature parity and build an unsigned sideload IPA | M3 | P2 | in_progress | Codex root iOS | INT-001, QA-033; read task handoff |
| [QR-001](tasks/QR-001.md) � Account-string QR is presented as a payment QR | M1 | P1 | implemented | Codex root | SEC-002; read task handoff |
| [QR-002](tasks/QR-002.md) � Debtor storage authorization may reject private QR reads | M1 | P1 | implemented | Codex root | SEC-002; read task handoff |
| [QR-003](tasks/QR-003.md) � Saved QR has no edit/replacement flow | M1 | P2 | implemented | Codex root | SEC-002; read task handoff |
| [QR-004](tasks/QR-004.md) � Signed QR views become stale | M1 | P2 | implemented | Codex root | SEC-002; read task handoff |
| [QR-005](tasks/QR-005.md) � Preferred method and removal state are wrong | M1 | P2 | implemented | Codex root | SEC-002; read task handoff |
| [QR-006](tasks/QR-006.md) � QR validation, same-phone use and profile visibility are incomplete | M1 | P2 | implemented | Codex root | SEC-002; read task handoff |
| [REL-001](tasks/REL-001.md) � Validate signed candidate and record release handoff | M3 | P1 | in_progress | Codex root | QA-001, AND-005; read task handoff |
| [SEC-001](tasks/SEC-001.md) � Cold-launch lock bypass and PIN navigator failure | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [SEC-002](tasks/SEC-002.md) � Pair balance helper lacks caller authorization | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [SEC-003](tasks/SEC-003.md) � PIN verification has no throttling | M1 | P2 | implemented | Codex root | INT-001; read task handoff |
| [SEC-004](tasks/SEC-004.md) � Old account loads can commit after session change | M1 | P1 | implemented | Codex root | INT-001; read task handoff |
| [SEC-005](tasks/SEC-005.md) � Privacy, export and deletion journeys are absent | M1 | P2 | implemented | Codex root | INT-001; read task handoff |

## Open release gates

- M1 implementation exists; tasks stay open until required acceptance and review evidence passes.
- Required backend/device checks cannot be closed by source inspection or mocks.
- Exact signed artifact, upgrade compatibility, applied migrations and authorization required before publishing.
- M2 capabilities remain hidden until verified; development does not waive incomplete M1 dependencies.
