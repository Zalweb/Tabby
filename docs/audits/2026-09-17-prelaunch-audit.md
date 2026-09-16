# Tabby pre-launch audit — 2026-09-17

## Decision

Tabby is **not launch-ready**. The app has confirmed crash, authorization, payment-integrity, storage, schema-drift, and release-signing blockers. Passing automated tests does not override these findings because most tests use mocked repositories and do not exercise two authenticated users against the live database.

No production Flutter or Supabase code was changed during this audit. This document records evidence and the required remediation order.

## Scope and method

Audited the Flutter client, Supabase migrations and live project metadata, Android/iOS build configuration, release artifacts, landing/docs pages, and existing tests. Checks included:

- Static review of routing, forms, async state, repository calls, error handling, permissions, storage, and RLS.
- Flutter analyzer and complete test suite.
- A focused widget lifecycle probe for the reported Add Friend crash, including closing the sheet while lookup is pending.
- Live Supabase read-only metadata checks and rollback-only friend-request acceptance checks.
- Android release artifact inspection, signing verification, connected-device package/version inspection, and public download-link checks.
- Review of responsive widget tests and identification of scenarios not covered by automation.

## Severity summary

| Severity | Count | Launch decision |
| --- | ---: | --- |
| Critical | 6 | Must fix before any distribution |
| High | 8 | Must fix before real users or financial data |
| Medium | 7 | Fix before broad release; some can follow a private alpha |
| Low | 3 | Fix during hardening |

## Critical launch blockers

### C-01 — Connect-by-ID Add Friend can crash the Flutter framework

**Status: Confirmed.**

**Evidence:** lib/features/profile/presentation/profile_screen.dart:2248-2481, especially the local TextEditingController, async findFriend(), nested StatefulBuilder, and whenComplete(codeController.dispose) at line 2481. The focused lifecycle probe reproduced both the reported _dependents.isEmpty assertion and a TextEditingController was used after being disposed error when the sheet was closed while the lookup was still completing. A separate probe of the regular manual Add Friend flow did not reproduce the crash, so this is specifically the Connect-by-ID sheet lifecycle.

**Impact:** A normal user action can terminate or corrupt the navigation tree. The user can lose the current form and be left with an unusable screen.

**Required fix:** Make the lookup sheet a dedicated StatefulWidget that owns and disposes its controller in dispose, invalidates or cancels pending work before route removal, and never updates a StatefulBuilder after its sheet is closing. Add regression tests for close-during-lookup and close-during-send, followed by a real-device run.

### C-02 — Live public.users policy exposes every registered profile

**Status: Confirmed against live Supabase metadata.**

**Evidence:** Live policy "Users can view all registered user profiles" is SELECT for authenticated with qual: true. It remains active beside the intended restricted policy. The affected columns include id, email, phone, display_name, avatar_url, and friend_code. Source hardening at supabase/migrations/20260917000001_authz_hardening.sql does not drop this stale policy, although older source/schema files attempt to do so.

**Impact:** Any signed-in user can enumerate all users' contact details and shareable IDs, violating privacy and enabling scraping, spam, and targeted abuse.

**Required fix:** Deploy an explicit migration that drops the stale policy, verifies the remaining policy definitions, and limits profile reads to self and an established connection/tab relationship. Add a live authenticated negative test that attempts to select another unrelated user's email, phone, and friend code.

### C-03 — Payment-proof storage is readable and writable by unrelated users

**Status: Confirmed against live Supabase metadata.**

**Evidence:** Live storage.objects contains broad policies "Authenticated users can view payment proofs" and "Authenticated users can upload payment proofs" constrained only by bucket_id = payment-proofs. There is also "Tab members can upload payment proofs" with the same effective cross-user scope. The bucket is private, but these object policies govern access to its contents. The intended source policy is at supabase/migrations/20260913000004_storage_and_triggers.sql:38-107; it also contains an unsafe generic receipts upload-folder exception that should not be retained.

**Impact:** Any authenticated user can read other people's payment screenshots and upload arbitrary objects into the payment-proof bucket. Payment screenshots may contain names, account numbers, and transaction references.

**Required fix:** Drop all broad policy names explicitly, enforce a user-owned path and/or a payment/tab-membership join for reads, constrain inserts to the submitting user and a server-created payment relationship, and test unrelated-user read/upload denial with signed and direct URLs.

### C-04 — tab_members insert authorization can cross tab boundaries

**Status: Confirmed in live policy and source.**

**Evidence:** The live insert policy contains the self-comparison tm.tab_id = tm.tab_id instead of comparing the inner row to the policy row. The same bug exists at supabase/migrations/20260917000001_authz_hardening.sql:64-70 and supabase/schema_all.sql:627. Any authenticated user who is an admin in one tab can satisfy the admin branch while inserting a membership for an unrelated tab. Live update/delete policies also allow any member to update or delete membership rows in that tab without an admin/self restriction (schema_all.sql:641-646).

**Impact:** A tab admin can grant access to arbitrary users in unrelated tabs; an ordinary member can potentially alter or remove other members. This compromises financial privacy and tab integrity.

**Required fix:** Qualify policy references, restrict membership mutation to tab admins plus a self-leave path, and add two-user cross-tab negative tests.

### C-05 — Live get_or_create_contact_tab is callable without ownership checks

**Status: Confirmed against live function metadata; not present in current local migrations.**

**Evidence:** The live SECURITY DEFINER function get_or_create_contact_tab(uuid,text) has no fixed search_path, grants execute to anon and authenticated, and accepts p_owner_id without requiring it to equal auth.uid(). Its body inserts contacts/tabs for the supplied owner. rg found no definition in supabase/migrations or supabase/schema_all.sql, indicating migration drift.

**Impact:** An unauthenticated or unrelated authenticated caller can create contacts/tabs for another owner, pollute their data, and cause denial-of-service-style record growth. The function also expands the attack surface because it is not tracked in the repository.

**Required fix:** Revoke EXECUTE from anon and public, require an authenticated caller and p_owner_id = auth.uid(), set search_path = public, pg_temp, and add the function to versioned migrations. Prefer a single audited RPC with server-side ownership checks.

### C-06 — Distributed Android release APK uses the debug signing key; iOS IPA is unsigned

**Status: Confirmed from build configuration and artifact inspection.**

**Evidence:** android/app/build.gradle.kts:27-32 sets the release signingConfig to signingConfigs.getByName("debug"). .github/workflows/build-android.yml:60-69 builds release without injecting a production keystore. The inspected APK is version 1.0.1 and verifies only against an Android debug certificate. .github/workflows/build-ios.yml:91-102 runs flutter build ipa --no-codesign --release.

**Impact:** The Android package is not a trusted production identity, can conflict with Google OAuth SHA configuration, and cannot support a safe signed update chain. The iOS artifact is not installable as a normally signed app and cannot be treated as a friend-download release.

**Required fix:** Create a protected production Android keystore and GitHub secret, sign CI releases with it, register its SHA-1/SHA-256 for Google OAuth, and verify upgrade/install behavior. Configure Apple signing, provisioning, bundle identifiers, and a macOS CI release path; verify the IPA is signed and installable on a test iPhone/iPad.

## High-severity functional and data-integrity findings

### H-01 — Debtor payment submission is rejected by RLS but shown as successful

**Evidence:** lib/features/tabs/application/tabby_providers.dart:450-597 optimistically adds a settled payment and calls recordPayment with confirmedByUserId: currentUserId for both directions. lib/features/tabs/data/supabase_tabby_repository.dart:1178-1219 sends status: submitted while also sending confirmed_by and confirmed_at for the debtor path. The live payment insert policy permits a self-submitted payment only with those confirmation fields null. lib/features/tabs/presentation/tab_detail_screen.dart:973-1005 does not await the call, immediately closes the sheet, and shows “Settlement recorded successfully!”. Repository errors are caught and discarded.

**Impact:** A debtor can believe a payment was recorded when Supabase rejected it. The local device can show a settled balance that another device does not see. Creditor recording also inserts a new confirmed payment rather than confirming an existing submitted payment, allowing duplicate/incorrect settlement records.

**Required fix:** Separate submit and confirm commands, enforce amount <= outstanding balance, await the result, return a typed success/error result, roll back optimistic state on failure, and implement an atomic server-side confirmation transition.

### H-02 — Receipt attachment is a fake success path; no image is uploaded

**Evidence:** lib/features/tabs/presentation/tab_detail_screen.dart:1354-1358 and 1497-1501 generate receipt_<timestamp>.png; lib/features/tabs/presentation/add_expense_modal.dart:703-717 does the same. image_picker is declared in pubspec.yaml:38 but unused in lib. supabase_tabby_repository.dart:1237-1245 only writes a string into transactions.receipt_url; it does not upload to Storage. The UI reports attachment success.

**Impact:** Users cannot provide payment proof and may think a nonexistent receipt is available. The current storage security review cannot be validated through the actual client flow.

**Required fix:** Implement picker/camera permission handling, upload bytes to an ownership-scoped Storage path, persist the returned path, render only authorized signed URLs, handle cancellation/errors, and verify persistence from a second authenticated client.

### H-03 — Live schema is missing payment-profile columns the client writes

**Evidence:** Local schema declares gcash_number, maya_number, and qr_code_url at supabase/migrations/20260913000001_core_schema.sql:22-32 and supabase/schema_all.sql:27-37. Live public.users currently has only id,email,phone,display_name,avatar_url,created_at,updated_at,friend_code. updateUserProfile writes those missing columns at lib/features/tabs/data/supabase_tabby_repository.dart:629-654 but catches the error at 658-660; the UI can therefore report saved state without persistence.

**Impact:** Payment contact information and QR settings do not reliably save or load in production. Users can pay the wrong number or lack the details they expect.

**Required fix:** Reconcile migrations with the live database, deploy and verify the columns, then make profile writes return errors instead of swallowing them. Add a read-after-write test.

### H-04 — Expense and group writes are multi-step and silently partial

**Evidence:** lib/features/tabs/data/supabase_tabby_repository.dart:1017-1175 inserts a transaction and then inserts participants in separate requests. An inserted transaction can remain if participant insertion fails. Group creation at 922-1013 similarly performs sequential group/member/tab writes and returns null after catching errors. The provider optimistically updates local/cache state before cloud confirmation.

**Impact:** Orphan transactions, incomplete participant sets, inconsistent balances, and divergence between devices are possible under transient failures or concurrent access.

**Required fix:** Use one audited RPC/transaction for expense and group creation, validate participant totals server-side, return typed errors, and update local state only after durable success or mark it explicitly pending for retry.

### H-05 — Transaction attachment URL can be changed by any tab member

**Evidence:** Live transactions allow any tab member to update a transaction. The prevent_transaction_tampering trigger guards many financial fields but does not guard receipt_url. attachReceipt updates the field directly at lib/features/tabs/data/supabase_tabby_repository.dart:1237-1245.

**Impact:** A tab member can replace or remove another user's proof reference, undermining auditability and potentially pointing it at unauthorized content.

**Required fix:** Restrict receipt updates to the uploader/transaction creator or an explicit proof workflow, validate the Storage path against the payment/transaction, and include receipt_url in tamper protection or a dedicated append-only proof table.

### H-06 — Offline state is not detected and failed writes are presented as success

**Evidence:** connectivity_plus is declared in pubspec.yaml:42 but unused. SupabaseTabbyRepository.isConnected at line 37 only reports initialization, not network reachability. fetchTabs returns an empty list on failure (821-887), while the provider merges cached data. Write methods catch errors and return void. There is no offline queue, retry, conflict policy, or visible pending-sync state. The profile diagnostics label the cache “Drift Local Cache” although the implementation uses flutter_secure_storage (tabby_local_cache.dart:3 and profile screen around 2064).

**Impact:** Slow or unavailable internet can show stale/empty data, claim that payments/expenses succeeded, and lose user actions. A second device may show a different balance.

**Required fix:** Add request timeouts, reachability plus Supabase health checks, durable pending operations with idempotency keys, retries/backoff, conflict handling, and explicit pending/error UI. Test airplane mode, packet loss, process kill, resume, and recovery.

### H-07 — Manual Add Friend uses a fabricated phone number when phone is blank

**Evidence:** profile_screen.dart:2573-2634, including the fallback +63 900 000 0000 around line 2619.

**Impact:** Multiple contact records can collide on a placeholder unique phone value, or a real person can later be associated with inaccurate contact data. Backend failure is hidden behind a success message.

**Required fix:** Store null/absent phone, validate at the boundary, require a real phone or email only when the chosen flow needs it, and return a clear result from contact creation.

### H-08 — Authentication edge cases and controller lifecycle are incomplete

**Evidence:** login_screen.dart and signup_screen.dart create TextEditingControllers but do not provide a dispose override. The native Google success-false branch in login_screen.dart:129-133 calls setState without a mounted guard after awaits. Forgot-password creates another local controller around line 171. The exact Connect-by-ID lifecycle issue is tracked separately as C-01.

**Impact:** Repeated navigation can leak controllers; delayed auth completion can produce a second lifecycle exception. Email-confirmation, Google-native, and browser-fallback behavior is not proven on real devices.

**Required fix:** Dispose every controller, guard all post-await UI mutations, centralize auth result/error mapping, and run real email/password and Google tests on Android and iOS with confirmation enabled.

## Medium and low findings

### M-01 — Onboarding completion is not persisted

onboarding_screen.dart:38-40 only changes an in-memory notifier, while AppState.hasSeenOnboarding starts false (lib/core/config/app_state.dart:3-5). A process restart can show onboarding again. Persist the flag in a small versioned local store and test cold start.

### M-02 — Profile avatar and QR actions are placeholders

Avatar actions around profile_screen.dart:1144-1225 store synthetic asset labels instead of reading camera/gallery output. QR management around line 1569 sets https://tabby.ph/qr/<user-id>_qrph.png after a delay; it does not create an image. This should not be presented as a working payment feature.

### M-03 — Sync diagnostics reports static health and false completion

The profile diagnostics sheet around profile_screen.dart:2015-2089 shows fixed Connected, Synchronized, and Enforced states, and reports success immediately without awaiting the refresh. Bind it to real sync state and show failure/pending states.

### M-04 — Public landing/docs release notes are inserted as unsanitized HTML

docs/app.js:58-67,132-135 and the identical landing/app.js implementation transform remote GitHub release notes and assign them to changelogBody.innerHTML. The markdown conversion does not HTML-escape input. Add escaping/safe Markdown rendering and a restrictive CSP; treat release-note content as untrusted.

### M-05 — Web security headers are incomplete

docs/vercel.json and landing/vercel.json set frame/content-type/referrer headers but no CSP, HSTS, Permissions-Policy, or robust cache policy. Add headers appropriate to the static site and verify the deployed response, especially if changelog rendering remains dynamic.

### M-06 — Financial split invariant is not enforced by the write path

The database has validate_transaction_split, but logExpense does not call it before inserting. There is no automatic constraint that participant allocations sum to the transaction total. Move validation into an atomic RPC/trigger and test odd-cent splits, zero shares, duplicate payer rows, and group membership changes.

### M-07 — Migration/live-schema drift is not detected in CI

The live database contains a function missing from source and stale policy definitions differ from repository SQL. Add schema diff checks, migration application to a clean database, and a production metadata smoke test that fails on unexpected policies/functions/columns.

### L-01 — Dependency maintenance warning

flutter analyze reports 60 packages with newer incompatible versions. This is not by itself a launch blocker, but versions should be reviewed, pinned, and updated deliberately after regression testing.

### L-02 — Test-only secure-storage plugin warning

The full test run logs MissingPluginException while clearing secure storage. This indicates an incomplete test platform mock. Make the cache abstraction injectable and test failure behavior explicitly; do not treat the warning as proof that production storage is healthy.

### L-03 — Current connected tablet is not running the current release

The connected tablet package inspection reported version 1.0.0/code 1, while the current release artifact is 1.0.1/code 2. Device testing must be repeated with the signed candidate build after the blockers are fixed.

## Verified positives

- flutter analyze: no issues found.
- Full Flutter suite: 107 tests passed.
- Focused friend profile tests: 2 tests passed.
- Live rollback-only friend journey passed: find by shareable ID, send request, accept request, canonical bilateral tab, two memberships, and visibility checks.
- Live RLS is enabled on the 16 inspected public tables.
- Friend RPCs are SECURITY DEFINER, use a controlled search path, require authenticated execution, and enforce caller identity in the inspected definitions.
- No committed Supabase service-role key, Supabase PAT, or Google private credential was found by secret-pattern scanning. The publishable/anon key in a mobile client is not a secret; any service/PAT that was shared outside a trusted private channel should still be rotated.
- Public direct APK and IPA download URLs currently return the expected assets; there is no ZIP asset at the tested ZIP URL.
- Android artifact is zip-aligned and structurally verifiable, but it is not production-signed (C-06).

## Scenarios not fully testable in this environment

These require external devices, accounts, or deployment controls and must remain open acceptance criteria:

1. Two real authenticated accounts on two devices completing Add Friend, acceptance, shared tab creation, expense, partial payment, proof upload, confirmation, rejection, and final balance convergence.
2. Google OAuth on the production Android package signature and on a signed iOS/iPadOS build, including browser fallback and redirect return.
3. Apple signing/provisioning and installation of the IPA on a real iPhone/iPad.
4. Email confirmation, password reset delivery, expired links, revoked sessions, account deletion, and token refresh after process restart.
5. Throttled/unstable network, airplane mode, background/foreground transitions, process termination during writes, and retry/conflict resolution.
6. Real Storage object isolation using unrelated authenticated users and actual signed URLs.
7. Concurrent expense/payment writes from multiple devices, duplicate taps, replayed requests, and race conditions against a non-empty production-like dataset.
8. Full accessibility, keyboard/IME behavior, rotation, small Android devices, notches/safe areas, and iOS-specific modal/navigation behavior.

## Required remediation order

**P0 before any user distribution:** C-01 through C-06; H-01; H-03; H-04; H-05; rotate any exposed service credentials; deploy and verify corrected live policies.

**P1 before financial beta:** H-02, H-06, H-07, H-08, M-02, M-03, M-06, M-07; complete two-account device testing.

**P2 before broad release:** M-01, M-04, M-05, L-01, L-02, and the full responsive/accessibility matrix.

The app should not be described as ready until P0 is closed and the previously untestable scenarios have recorded evidence.
