# Tabby security best-practices report

Date: 2026-09-17
Scope: Flutter client, Supabase live metadata, SQL migrations, Storage policy definitions, build/release configuration, and public landing/docs JavaScript.

## Overall assessment

The project has useful RLS and authenticated RPC controls, but the live project has policy drift and several authorization boundaries are unsafe. The application must not be released to real users until S1-S7 are remediated and tested with unrelated authenticated accounts.

## Findings

### S1 — Unrestricted authenticated read of all user profiles

- **Severity:** Critical
- **Location:** Live public.users policy "Users can view all registered user profiles"; intended policy source supabase/migrations/20260913000002_rls_policies.sql:73-90.
- **Evidence:** The live policy is SELECT, role authenticated, predicate true. It coexists with the restricted connected-party policy.
- **Impact:** Any signed-in user can enumerate email, phone, display name, avatar, and shareable friend IDs for every account.
- **Fix:** Drop the stale policy in a corrective migration; retain only self/connected-party access or a narrowly scoped sanitized search RPC. Add an unrelated-user negative test.
- **Mitigation:** Until deployed, do not onboard real users; revoke or rotate affected user contact data if enumeration may have occurred.
- **False-positive notes:** This is not inferred from source alone; it was observed in live metadata on the audit date.

### S2 — Payment-proof Storage policies are bucket-wide

- **Severity:** Critical
- **Location:** Live storage.objects policies "Authenticated users can view payment proofs", "Authenticated users can upload payment proofs", and "Tab members can upload payment proofs"; source supabase/migrations/20260913000004_storage_and_triggers.sql:38-107.
- **Evidence:** Live SELECT/INSERT conditions effectively require only bucket_id = payment-proofs. The source policy also includes a generic first-folder receipts upload exception.
- **Impact:** Unrelated authenticated users can read sensitive payment images and upload arbitrary objects; object paths may be used to confuse proof references.
- **Fix:** Remove all broad policies. Use user-owned paths for upload; for reads, require the uploader or an existence check through a payment/transaction whose tab includes auth.uid(). Keep the bucket private and issue short-lived signed URLs only after authorization.
- **Mitigation:** Disable proof upload/read features until corrected; audit existing objects and access logs.
- **False-positive notes:** A private bucket alone does not fix an overbroad storage.objects RLS policy.

### S3 — Cross-tab membership authorization bug and overbroad mutation

- **Severity:** Critical
- **Location:** Live tab_members INSERT policy; source supabase/migrations/20260917000001_authz_hardening.sql:64-70, supabase/schema_all.sql:627; UPDATE/DELETE source schema_all.sql:641-646.
- **Evidence:** The admin check uses the tautology tm.tab_id = tm.tab_id rather than comparing the selected row to the policy row. UPDATE/DELETE only require membership in the tab and do not require admin status or self-leave.
- **Impact:** An admin of one tab can grant access to another tab; members may modify/remove other membership records. This is an authorization and integrity bypass.
- **Fix:** Qualify all row references; restrict insert/update/delete to tab admins, with a separately constrained self-leave operation. Add cross-tab negative tests using two unrelated tabs.
- **Mitigation:** Freeze membership mutation or revoke affected policies until a corrective migration is applied.
- **False-positive notes:** The tautology was found in both live policy text and checked-in SQL.

### S4 — Untracked SECURITY DEFINER contact-tab function accepts arbitrary owner IDs

- **Severity:** Critical
- **Location:** Live public.get_or_create_contact_tab(uuid,text); no matching definition under supabase/migrations or supabase/schema_all.sql.
- **Evidence:** The live function is executable by anon and authenticated, has no fixed search_path, does not compare p_owner_id with auth.uid(), and inserts records for the supplied owner.
- **Impact:** Unauthenticated or unrelated callers can create contacts/tabs for arbitrary owners and grow or pollute their data.
- **Fix:** Revoke EXECUTE from public and anon, grant only to authenticated if needed, require p_owner_id = auth.uid(), set search_path = public, pg_temp, and track the function in migrations. Prefer a safe replacement RPC.
- **Mitigation:** Revoke execution immediately and inspect or remove unauthorized records after preserving audit evidence.
- **False-positive notes:** This is a live metadata finding; no mutation was performed during the audit.

### S5 — Release identity and update-chain weakness

- **Severity:** Critical
- **Location:** android/app/build.gradle.kts:27-32; .github/workflows/build-android.yml:60-69; .github/workflows/build-ios.yml:91-102.
- **Evidence:** Android release uses the debug signing config; iOS CI uses --no-codesign.
- **Impact:** Android users receive a non-production-signed package, and iOS output is not a normally installable signed release. Google OAuth and future update trust can fail or be misconfigured.
- **Fix:** Store production signing materials in CI secrets, sign Android/iOS release builds, validate certificates and package identity, and bind OAuth to the production signatures.
- **Mitigation:** Do not distribute current artifacts beyond internal testing.
- **False-positive notes:** APK structural verification and zip alignment do not establish production signing.

### S6 — Unsanitized remote release notes reach innerHTML

- **Severity:** High
- **Location:** docs/app.js:58-67,132-135; identical code in landing/app.js.
- **Evidence:** Remote GitHub release notes are transformed by a regex markdown helper without HTML escaping and assigned to changelogBody.innerHTML.
- **Impact:** A malicious or compromised release note can execute script in the public site origin, potentially manipulating downloads or collecting visitor data.
- **Fix:** Escape all text or use a vetted Markdown parser with HTML disabled and URL scheme allowlisting. Add a restrictive CSP and deploy headers. Test malicious release-note fixtures.
- **Mitigation:** Remove dynamic HTML rendering or serve release notes as plain text until sanitized.
- **False-positive notes:** Exploitability depends on control of release-note content, but the sink is reachable from remote data and should be treated as untrusted.

### S7 — Receipt URL is mutable by any tab member and is not covered by tamper protection

- **Severity:** High
- **Location:** lib/features/tabs/data/supabase_tabby_repository.dart:1237-1245; live transaction update policy and prevent_transaction_tampering trigger.
- **Evidence:** The client updates transactions.receipt_url directly. The trigger protects many financial fields but not this field, and the update policy is member-scoped rather than proof-owner-scoped.
- **Impact:** A member can replace a proof reference or point it at unauthorized content, weakening auditability and creating phishing or confusion opportunities.
- **Fix:** Use an append-only proof record or restrict updates to the uploader/creator; validate that paths belong to the associated payment/tab.
- **Mitigation:** Disable receipt attachment until the Storage and database proof workflow is corrected.
- **False-positive notes:** This does not by itself alter amount fields, but proof integrity is security-relevant for payment disputes.

## Controls that were verified

- No committed service-role key, Supabase PAT, or private Google credential was found by repository secret-pattern scanning.
- The mobile Supabase URL and publishable key are client configuration, not service secrets; the service/PAT values supplied during the project should never be committed or shipped.
- All 16 inspected public tables had RLS enabled.
- Friend search/request/response RPCs use authenticated execution and caller checks in the live definitions.
- Balance/dashboard RPCs check that the requested user is auth.uid().

## Security verification still required

1. Test all S1-S4 policies with two unrelated authenticated users and an anonymous client.
2. Test Storage direct download and signed URLs for unrelated users, including guessed paths.
3. Run migration drift checks against a clean database and the production metadata.
4. Test revoked sessions, token refresh, account deletion, and stale cached data after logout.
5. Rotate service/PAT credentials if they were exposed outside the trusted project context, then verify old credentials fail.
