# Android review register — 2026-10-31

Baseline d33d716a52461ce70c4f086bb20f4c68f3bd58d6. Source review covered Flutter screens/state/repositories, Android configuration, SQL migrations and release workflows. Previous session reported 247 tests passing and clean analysis; five focused probe scenarios reproduced identity merge, expense merge, group payment, malformed currency and app-lock failures. Probes were removed. This is historical baseline evidence, not a rerun or remediation claim. No connected Android device or live database verification was available.

Each finding remains open until its task acceptance and verification records support closure. Source-confirmed means implementation evidence; production exposure is not assumed. Investigations can be disproved only with recorded evidence and an explained disposition.

## AUD-20261031-001

**Different people merge by display name** — P1; confirmed-reproduced.

- Problem: Different people merge by display name.
- Impact: Balances and history can be attributed to another relationship.
- Recommended fix: Use immutable party/group IDs and explicit temporary-to-server mappings; remove name fallbacks.
- Acceptance: Two registered Alex accounts and two same-name groups remain separate after refresh and restart.
- Source: [implementation](../../lib/features/tabs/data/mock_tabby_repository.dart).
- Disposition: tracked by [LED-001](../progress/tasks/LED-001.md); task record is authoritative for current status.

## AUD-20261031-002

**Distinct same-price expenses disappear** — P1; confirmed-reproduced.

- Problem: Distinct same-price expenses disappear.
- Impact: A real financial obligation can be hidden during local/server reconciliation.
- Recommended fix: Merge only matching operation/transaction identities; similarity may only trigger a warning.
- Acceptance: Lunch and Coffee at the same price ten minutes apart both survive local/server refresh.
- Source: [implementation](../../lib/features/tabs/data/mock_tabby_repository.dart).
- Disposition: tracked by [LED-002](../progress/tasks/LED-002.md); task record is authoritative for current status.

## AUD-20261031-003

**Retries can duplicate server writes** — P1; confirmed-source.

- Problem: Retries can duplicate server writes.
- Impact: A committed write with a lost response may be inserted again.
- Recommended fix: Add stable operation IDs to versioned RPCs and server uniqueness; route immediate and replay writes through one executor.
- Acceptance: Drop the response after commit and retry concurrently; exactly one expense/payment exists.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [LED-003](../progress/tasks/LED-003.md); task record is authoritative for current status.

## AUD-20261031-004

**Failed operations can continuously retry** — P1; confirmed-source.

- Problem: Failed operations can continuously retry.
- Impact: Permanent rejection can consume battery and repeat backend calls.
- Recommended fix: Remove recursive refresh/replay triggering; classify failures and back off bounded transient retries.
- Acceptance: Permanent failures become needsAttention; retry count does not grow while idle; transient retries are delayed.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [LED-004](../progress/tasks/LED-004.md); task record is authoritative for current status.

## AUD-20261031-005

**Contact payer and settlement paths lose synchronization** — P1; confirmed-source.

- Problem: Contact payer and settlement paths lose synchronization.
- Impact: Local success can fail to reach other devices or survive reinstall.
- Recommended fix: Support contact PartyRef in atomic expense and manual receipt operations; never silently discard a rejected operation.
- Acceptance: A contact can pay or owe; expenses and partial cash settlements persist through refresh/restart.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [LED-005](../progress/tasks/LED-005.md); task record is authoritative for current status.

## AUD-20261031-006

**Sync diagnostics overstate success** — P2; confirmed-source.

- Problem: Sync diagnostics overstate success.
- Impact: Users may trust stale balances or unsent records.
- Recommended fix: Return structured fetch/queue results and show pending/failed counts and last successful sync.
- Acceptance: Server errors with connectivity available show failure, retain cache and never report synchronized.
- Source: [implementation](../../lib/features/profile/application/sync_diagnostics_provider.dart).
- Disposition: tracked by [LED-006](../progress/tasks/LED-006.md); task record is authoritative for current status.

## AUD-20261031-007

**Group payments change uninvolved balances** — P1; confirmed-reproduced.

- Problem: Group payments change uninvolved balances.
- Impact: Bob paying Carol incorrectly changes Alice balance.
- Recommended fix: Preserve recipient in fetch/model/cache and apply payments only to the payer and recipient.
- Acceptance: Bob-to-Carol payment leaves Alice unchanged on server, cache, UI and after refresh.
- Source: [implementation](../../lib/features/tabs/data/supabase_tabby_repository.dart).
- Disposition: tracked by [GRP-001](../progress/tasks/GRP-001.md); task record is authoritative for current status.

## AUD-20261031-008

**Group shares and payer selection are incomplete** — P1; confirmed-source.

- Problem: Group shares and payer selection are incomplete.
- Impact: Existing-group defaults and aggregate counterpart shares produce wrong allocations.
- Recommended fix: Use actual member count, explicit payer selection and individual shares throughout UI/RPC.
- Acceptance: Three/five-member odd-cent bills calculate correctly for each possible payer and perspective.
- Source: [implementation](../../lib/features/tabs/presentation/add_expense_modal.dart).
- Disposition: tracked by [GRP-002](../progress/tasks/GRP-002.md); task record is authoritative for current status.

## AUD-20261031-009

**Group settlement treats a group as a person** — P1; confirmed-source.

- Problem: Group settlement treats a group as a person.
- Impact: Payment and QR lookup cannot resolve the proper recipient.
- Recommended fix: Present who-pays-whom obligations and select an actual member recipient.
- Acceptance: Group debtor opens the actual creditor QR and settles only that pair obligation.
- Source: [implementation](../../lib/features/tabs/presentation/tab_detail_screen.dart).
- Disposition: tracked by [GRP-003](../progress/tasks/GRP-003.md); task record is authoritative for current status.

## AUD-20261031-010

**Group creation is partially committed** — P2; confirmed-source.

- Problem: Group creation is partially committed.
- Impact: Membership failure leaves incomplete group/tab records.
- Recommended fix: Create group, members, tab and tab memberships in one authenticated transaction.
- Acceptance: Inject failure at each step; no partial group remains and a retry creates one complete group.
- Source: [implementation](../../lib/features/tabs/data/supabase_tabby_repository.dart).
- Disposition: tracked by [GRP-004](../progress/tasks/GRP-004.md); task record is authoritative for current status.

## AUD-20261031-011

**Malformed currency is accepted or throws without feedback** — P2; confirmed-reproduced.

- Problem: Malformed currency is accepted or throws without feedback.
- Impact: Invalid text can turn into a smaller valid amount or break submission.
- Recommended fix: Validate complete decimal input and catch parsing errors inline; accept PHP up to 999999999.99, maximum two decimals, no exponent or malformed grouping.
- Acceptance: Reject abc.50, 1.234, exponent and overflow input; accept valid formatted PHP exactly.
- Source: [implementation](../../lib/core/utils/currency_formatter.dart).
- Disposition: tracked by [GRP-005](../progress/tasks/GRP-005.md); task record is authoritative for current status.

## AUD-20261031-012

**Documented ledger capabilities are absent** — P2; confirmed-source.

- Problem: Documented ledger capabilities are absent.
- Impact: Acknowledgment, proposals, disputes, recurrence and splits are claimed without complete journeys.
- Recommended fix: Track M2 capabilities separately; implement audited corrections/cancellation in M1 and remove unsupported claims.
- Acceptance: Every missing capability maps to a task and hidden/available behavior matches its verified status.
- Source: [historical product specification](../archive/legacy-agents-2026-10-31.md).
- Disposition: tracked by [CAP-001](../progress/tasks/CAP-001.md); task record is authoritative for current status.

## AUD-20261031-013

**Account-string QR is presented as a payment QR** — P1; confirmed-source.

- Problem: Account-string QR is presented as a payment QR.
- Impact: Payers may receive an unusable wallet destination.
- Recommended fix: Remove generic text QR generation from receiving-method setup; upload wallet-exported receiving QR.
- Acceptance: Setup offers upload and rejects non-QR images; no generic account-number QR appears.
- Source: [implementation](../../lib/features/payment_methods/presentation/payment_methods_sheet.dart).
- Disposition: tracked by [QR-001](../progress/tasks/QR-001.md); task record is authoritative for current status.

## AUD-20261031-014

**Debtor storage authorization may reject private QR reads** — P1; needs-live-testing.

- Problem: Debtor storage authorization may reject private QR reads.
- Impact: Listing can succeed while signed image access fails.
- Recommended fix: Test effective policies as owner/friend/debtor/stranger; use a narrow authorization helper for specific method objects.
- Acceptance: Two authenticated accounts load a permitted image; stranger/anon and guessed paths fail.
- Source: [implementation](../../supabase/migrations/20260917000005_payment_methods.sql).
- Disposition: tracked by [QR-002](../progress/tasks/QR-002.md); task record is authoritative for current status.

## AUD-20261031-015

**Saved QR has no edit/replacement flow** — P2; confirmed-source.

- Problem: Saved QR has no edit/replacement flow.
- Impact: A changed receiving destination cannot be updated safely.
- Recommended fix: Add edit/replace with upload-before-reference-switch and revision metadata; invalidate readers.
- Acceptance: Upload failure preserves old method; successful replacement appears on another device.
- Source: [implementation](../../lib/features/payment_methods/presentation/payment_methods_sheet.dart).
- Disposition: tracked by [QR-003](../progress/tasks/QR-003.md); task record is authoritative for current status.

## AUD-20261031-016

**Signed QR views become stale** — P2; confirmed-source.

- Problem: Signed QR views become stale.
- Impact: Expired URLs or old destinations remain cached.
- Recommended fix: Refresh on payment-flow entry and method changes; regenerate expiring/failed URLs once with explicit retry.
- Acceptance: Expire URL, reopen flow, update/remove method from another session; correct state appears.
- Source: [implementation](../../lib/features/payment_methods/application/payment_methods_provider.dart).
- Disposition: tracked by [QR-004](../progress/tasks/QR-004.md); task record is authoritative for current status.

## AUD-20261031-017

**Preferred method and removal state are wrong** — P2; confirmed-source.

- Problem: Preferred method and removal state are wrong.
- Impact: Adding clears local preference and deleting can leave the removed method visible.
- Recommended fix: Make preference promotion atomic and update remaining list before selecting a successor.
- Acceptance: Add nondefault preserves preference; remove default promotes exactly one remaining method.
- Source: [implementation](../../lib/features/payment_methods/application/payment_methods_provider.dart).
- Disposition: tracked by [QR-005](../progress/tasks/QR-005.md); task record is authoritative for current status.

## AUD-20261031-018

**QR validation, same-phone use and profile visibility are incomplete** — P2; confirmed-source.

- Problem: QR validation, same-phone use and profile visibility are incomplete.
- Impact: An arbitrary image can be saved and payers cannot easily import receiving QR into a wallet.
- Recommended fix: Validate readable QR, retain quiet zone, add fullscreen/save/share and authorized friend-profile access.
- Acceptance: Wallet import works on one phone; unreadable images fail; friend/debtor access matches the agreed matrix.
- Source: [implementation](../../lib/features/payment_methods/presentation/payment_method_payment_sheet.dart).
- Disposition: tracked by [QR-006](../progress/tasks/QR-006.md); task record is authoritative for current status.

## AUD-20261031-019

**Confirm Payment inserts a separate payment** — P1; confirmed-source.

- Problem: Confirm Payment inserts a separate payment.
- Impact: The original payer submission stays pending and history becomes ambiguous.
- Recommended fix: Confirm/reject a specific submitted payment ID; separate manual record-received action.
- Acceptance: Recipient confirms pending submission once; no additional payment row appears.
- Source: [implementation](../../lib/features/tabs/presentation/tab_detail_screen.dart).
- Disposition: tracked by [PAY-001](../progress/tasks/PAY-001.md); task record is authoritative for current status.

## AUD-20261031-020

**Submit Payment Proof does not attach payment proof** — P1; confirmed-source.

- Problem: Submit Payment Proof does not attach payment proof.
- Impact: The form has no proof and later attachment targets a transaction.
- Recommended fix: Attach optional proof/reference to the payment ID and authorize recipient access; preserve offline uploads.
- Acceptance: Payer submits proof offline/online and recipient sees it on the same payment.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [PAY-002](../progress/tasks/PAY-002.md); task record is authoritative for current status.

## AUD-20261031-021

**Receipt status claims verification without evidence** — P2; confirmed-source.

- Problem: Receipt status claims verification without evidence.
- Impact: Users can confuse attachment presence with actual verification; offline attachments can be lost.
- Recommended fix: Use Receipt attached copy; append proof revisions and persist upload/update operations.
- Acceptance: Unverified files never receive a verified label; offline attachment survives process death and sync.
- Source: [implementation](../../lib/features/tabs/presentation/tab_detail_screen.dart).
- Disposition: tracked by [PAY-003](../progress/tasks/PAY-003.md); task record is authoritative for current status.

## AUD-20261031-022

**Concurrent confirmations may overpay** — P1; needs-backend-testing.

- Problem: Concurrent confirmations may overpay.
- Impact: Separate pending rows can pass the balance check together.
- Recommended fix: Lock the obligation pair before rechecking and confirming; make duplicate confirmation idempotent.
- Acceptance: Concurrent confirmations whose sum exceeds debt cannot both succeed; exact debt never becomes overpaid.
- Source: [implementation](../../supabase/migrations/20261029000001_atomic_money_contract.sql).
- Disposition: tracked by [PAY-004](../progress/tasks/PAY-004.md); task record is authoritative for current status.

## AUD-20261031-023

**Cold-launch lock bypass and PIN navigator failure** — P1; confirmed-reproduced.

- Problem: Cold-launch lock bypass and PIN navigator failure.
- Impact: Private ledger starts visible; PIN unlock dialog cannot open.
- Recommended fix: Load security state before sensitive content; lock at cold start and use a valid navigator or inline unlock route.
- Acceptance: Cold launch is protected; PIN dialog opens on resume; cancellation leaves lock active.
- Source: [implementation](../../lib/core/widgets/biometric_gate.dart).
- Disposition: tracked by [SEC-001](../progress/tasks/SEC-001.md); task record is authoritative for current status.

## AUD-20261031-024

**Pair balance helper lacks caller authorization** — P1; confirmed-source-production-unverified.

- Problem: Pair balance helper lacks caller authorization.
- Impact: An authenticated outsider knowing IDs may query private balances.
- Recommended fix: Require caller party membership or revoke client execution of the internal helper; test effective production grants.
- Acceptance: Anon/stranger cannot query any pair balance; legitimate parties and internal RPCs still work.
- Source: [implementation](../../supabase/migrations/20261029000001_atomic_money_contract.sql).
- Disposition: tracked by [SEC-002](../progress/tasks/SEC-002.md); task record is authoritative for current status.

## AUD-20261031-025

**PIN verification has no throttling** — P2; confirmed-source.

- Problem: PIN verification has no throttling.
- Impact: Repeated guessing is unrestricted and verifier derivation is too cheap.
- Recommended fix: Use a versioned slow salted verifier; persist failed attempts, delay after five failures, and provide reauthenticated reset.
- Acceptance: Delay survives restart; correct PIN unlocks; legacy verifier upgrades only after successful verification.
- Source: [implementation](../../lib/core/services/pin_protection_service.dart).
- Disposition: tracked by [SEC-003](../progress/tasks/SEC-003.md); task record is authoritative for current status.

## AUD-20261031-026

**Old account loads can commit after session change** — P1; needs-runtime-testing.

- Problem: Old account loads can commit after session change.
- Impact: Late asynchronous responses can repopulate another session with stale data.
- Recommended fix: Scope requests/provider caches by account plus session generation and discard late results.
- Acceptance: Delay account A response, logout/login B, then release A response; no A data is rendered or cached as B.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [SEC-004](../progress/tasks/SEC-004.md); task record is authoritative for current status.

## AUD-20261031-027

**Privacy, export and deletion journeys are absent** — P2; confirmed-source.

- Problem: Privacy, export and deletion journeys are absent.
- Impact: Users cannot understand access or manage their data.
- Recommended fix: Add accurate privacy notice, caller-scoped export and reauthenticated deletion request; retain shared financial audit records with anonymization.
- Acceptance: Export has no unrelated data; deletion request is tracked and does not destroy confirmed shared records.
- Source: [implementation](../../lib/features/profile/presentation/profile_screen.dart).
- Disposition: tracked by [SEC-005](../progress/tasks/SEC-005.md); task record is authoritative for current status.

## AUD-20261031-028

**Startup errors can block authentication initialization** — P1; confirmed-source.

- Problem: Startup errors can block authentication initialization.
- Impact: Storage or notification failure can prevent usable startup.
- Recommended fix: Render startup state first; isolate initializers with retry and nonfatal service failures.
- Acceptance: Storage exception, notification exception and offline profile fetch each show recoverable UI.
- Source: [implementation](../../lib/main.dart).
- Disposition: tracked by [AUTH-001](../progress/tasks/AUTH-001.md); task record is authoritative for current status.

## AUD-20261031-029

**Password recovery and confirmation assistance are missing** — P2; confirmed-source.

- Problem: Password recovery and confirmation assistance are missing.
- Impact: Email users can be locked out without recovery.
- Recommended fix: Implement forgot/reset password, expired-link errors and rate-limited confirmation resend.
- Acceptance: Cold/warm valid recovery works; expired/used tokens fail safely; resend obeys service limits.
- Source: [implementation](../../lib/features/auth/presentation/login_screen.dart).
- Disposition: tracked by [AUTH-002](../progress/tasks/AUTH-002.md); task record is authoritative for current status.

## AUD-20261031-030

**Profile completion ignores failed method saves** — P2; confirmed-source.

- Problem: Profile completion ignores failed method saves.
- Impact: Users leave setup believing unsaved QR methods are available.
- Recommended fix: Track per-item save results; preserve drafts and retry failed methods idempotently before reporting completion.
- Acceptance: One upload fails among multiple methods; saved items do not duplicate and failure remains actionable.
- Source: [implementation](../../lib/features/auth/presentation/complete_profile_screen.dart).
- Disposition: tracked by [AUTH-003](../progress/tasks/AUTH-003.md); task record is authoritative for current status.

## AUD-20261031-031

**Phone validation and default wallet assumptions are weak** — P2; confirmed-source.

- Problem: Phone validation and default wallet assumptions are weak.
- Impact: Invalid phone strings or nonwallet numbers can become payment details.
- Recommended fix: Normalize supported Philippine phone forms consistently and require explicit wallet-account confirmation.
- Acceptance: 09/+639/639 equivalents normalize identically; invalid prefixes fail; profile phone does not automatically enable GCash.
- Source: [implementation](../../lib/features/auth/presentation/signup_screen.dart).
- Disposition: tracked by [AUTH-004](../progress/tasks/AUTH-004.md); task record is authoritative for current status.

## AUD-20261031-032

**Onboarding accessibility and back behavior need validation** — P2; needs-device-testing.

- Problem: Onboarding accessibility and back behavior need validation.
- Impact: Fixed slides and default back can overflow or exit unexpectedly.
- Recommended fix: Make slides scroll/adapt; system back returns to previous slide/step and prompts only for unsaved edits.
- Acceptance: Small/landscape/200 percent text screens remain usable; back follows steps then exits normally.
- Source: [implementation](../../lib/features/onboarding/presentation/onboarding_screen.dart).
- Disposition: tracked by [AUTH-005](../progress/tasks/AUTH-005.md); task record is authoritative for current status.

## AUD-20261031-033

**Dashboard labels and monthly filter misrepresent data** — P2; confirmed-source.

- Problem: Dashboard labels and monthly filter misrepresent data.
- Impact: Outstanding debt is labeled expense and all-time activity appears monthly.
- Recommended fix: Use You are owed/You owe and explicit rolling 24-hour/7-day/calendar-month activity filters.
- Acceptance: Boundary dates filter correctly and KPIs match outstanding obligations rather than spending.
- Source: [implementation](../../lib/features/home/presentation/home_dashboard_screen.dart).
- Disposition: tracked by [HOME-001](../progress/tasks/HOME-001.md); task record is authoritative for current status.

## AUD-20261031-034

**Settled reminders return after refresh** — P1; confirmed-source.

- Problem: Settled reminders return after refresh.
- Impact: Users can be reminded about obligations already paid.
- Recommended fix: Derive reminders from unresolved obligations; cancel old alarms on confirmation/cancellation.
- Acceptance: Settle dated debt, refresh/restart/reconnect: no reminder or overdue alert returns.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [HOME-002](../progress/tasks/HOME-002.md); task record is authoritative for current status.

## AUD-20261031-035

**Notification preferences and permissions are disconnected** — P1; confirmed-source.

- Problem: Notification preferences and permissions are disconnected.
- Impact: Alerts may be absent on fresh installs or persist after disable/logout.
- Recommended fix: Request permission from enable flow, enforce account-scoped preferences and cancel alarms/token association on logout.
- Acceptance: Fresh permission allow/deny, disable preferences and logout each produce the expected alert behavior.
- Source: [implementation](../../lib/core/services/tabby_notification_service.dart).
- Disposition: tracked by [HOME-003](../progress/tasks/HOME-003.md); task record is authoritative for current status.

## AUD-20261031-036

**Reminder sent state and closed-app delivery are unreliable** — P2; confirmed-source.

- Problem: Reminder sent state and closed-app delivery are unreliable.
- Impact: UI claims delivery before server acceptance; realtime requires a running connection.
- Recommended fix: Await queue acceptance, show sent/pending/failure accurately and add account-bound background push delivery.
- Acceptance: Offline/rejected sends do not claim sent; closed app receives accepted reminders and tap opens authorized target.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [HOME-004](../progress/tasks/HOME-004.md); task record is authoritative for current status.

## AUD-20261031-037

**Profile writes can report false success** — P2; confirmed-source.

- Problem: Profile writes can report false success.
- Impact: Local-only email and separate wallet fields mislead users.
- Recommended fix: Await profile persistence, verify auth email changes, and route all payment edits through saved methods.
- Acceptance: Server rejection preserves form; email changes only after verification; payment methods remain consistent.
- Source: [implementation](../../lib/features/tabs/application/tabby_providers.dart).
- Disposition: tracked by [PRO-001](../progress/tasks/PRO-001.md); task record is authoritative for current status.

## AUD-20261031-038

**Avatar camera/gallery choices are placeholders** — P2; confirmed-source.

- Problem: Avatar camera/gallery choices are placeholders.
- Impact: Preset assets are reported as actual uploads.
- Recommended fix: Implement image picker, durable upload and actual preview with cancel/error handling.
- Acceptance: Chosen gallery/camera image persists across restart; cancel does not report success.
- Source: [implementation](../../lib/features/profile/presentation/profile_screen.dart).
- Disposition: tracked by [PRO-002](../progress/tasks/PRO-002.md); task record is authoritative for current status.

## AUD-20261031-039

**Friend and group actions overstate persistence/deletion** — P2; confirmed-source.

- Problem: Friend and group actions overstate persistence/deletion.
- Impact: Edits disappear and backend removal failures are hidden.
- Recommended fix: Persist private nicknames, await unfriend/archive results, label archive accurately and support restore.
- Acceptance: Failure remains visible; archive restores; unfriending preserves tabs and financial records.
- Source: [implementation](../../lib/features/connections/presentation/connections_screen.dart).
- Disposition: tracked by [PRO-003](../progress/tasks/PRO-003.md); task record is authoritative for current status.

## AUD-20261031-040

**Preferences are partially implemented** — P3; confirmed-source.

- Problem: Preferences are partially implemented.
- Impact: USD/language choices do not consistently affect UI and dark mode is incomplete.
- Recommended fix: M1 is PHP/English only: remove unfinished choices; apply theme and reduced-motion preferences consistently.
- Acceptance: No nonfunctional preference remains; core screens pass light/dark/reduced-motion widget checks.
- Source: [implementation](../../lib/features/profile/presentation/profile_screen.dart).
- Disposition: tracked by [PRO-004](../progress/tasks/PRO-004.md); task record is authoritative for current status.

## AUD-20261031-041

**Android scheduled notification integration is incomplete** — P1; confirmed-source.

- Problem: Android scheduled notification integration is incomplete.
- Impact: Missing receivers and exact-alarm access can prevent reminders.
- Recommended fix: Add required receivers/reboot integration, request special access where needed and use an inexact fallback when denied.
- Acceptance: Scheduled reminder fires with permission allowed/denied fallback and survives reboot appropriately.
- Source: [implementation](../../android/app/src/main/AndroidManifest.xml).
- Disposition: tracked by [AND-001](../progress/tasks/AND-001.md); task record is authoritative for current status.

## AUD-20261031-042

**Secure-storage backup rules are absent** — P2; confirmed-source-runtime-unverified.

- Problem: Secure-storage backup rules are absent.
- Impact: Restored encrypted data may fail to decrypt and block startup.
- Recommended fix: Exclude secure storage/key-bound secrets from backup/transfer and make restore failure recoverable.
- Acceptance: Restore to another device does not crash; session/cache recover safely without exposing data.
- Source: [implementation](../../android/app/src/main/AndroidManifest.xml).
- Disposition: tracked by [AND-002](../progress/tasks/AND-002.md); task record is authoritative for current status.

## AUD-20261031-043

**Picker recovery and draft/back protection are missing** — P2; confirmed-source.

- Problem: Picker recovery and draft/back protection are missing.
- Impact: Process recreation and system back can lose user input.
- Recommended fix: Handle retrieveLostData, store drafts and implement PopScope for multistep entry and unsaved edits.
- Acceptance: Kill/recreate during picker, recover image/draft; back returns a step or asks before discarding edits.
- Source: [implementation](../../lib/core/services/receipt_attachment_service.dart).
- Disposition: tracked by [AND-003](../progress/tasks/AND-003.md); task record is authoritative for current status.

## AUD-20261031-044

**History loading and cache rewriting will scale poorly** — P2; needs-performance-testing.

- Problem: History loading and cache rewriting will scale poorly.
- Impact: Sequential RPCs, scans and full JSON rewrites can stall large histories.
- Recommended fix: Batch balances, page history, reconcile by IDs and migrate cache/queue to transactional Drift storage with keys kept in secure storage; benchmark before selecting encryption integration.
- Acceptance: Profile 100 tabs/10000 entries on low-memory Android; page rendering remains responsive and queue survives interrupted migration.
- Source: [implementation](../../lib/features/tabs/data/tabby_local_cache.dart).
- Disposition: tracked by [AND-004](../progress/tasks/AND-004.md); task record is authoritative for current status.

## AUD-20261031-045

**Automatic release can publish a debug-signed APK** — P1; confirmed-source-artifact-unverified.

- Problem: Automatic release can publish a debug-signed APK.
- Impact: Public updates may have the wrong signing identity.
- Recommended fix: Require release signing on every publishable path; verify certificate and exact candidate digest before upload; test upgrade and 16 KB native compatibility.
- Acceptance: Main/tag/manual publication cannot upload debug APK; installed prior release upgrades preserving data and OAuth works.
- Source: [implementation](../../.github/workflows/publish-latest-build.yml).
- Disposition: tracked by [AND-005](../progress/tasks/AND-005.md); task record is authoritative for current status.
