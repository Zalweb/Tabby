# AUTH-002 — Password recovery and confirmation assistance are missing

```json task-metadata
{
  "id": "AUTH-002",
  "area": "onboarding-and-auth",
  "title": "Password recovery and confirmation assistance are missing",
  "milestone": "M1",
  "priority": "P2",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "16cbdd83a108410be192c5387dbe25c0d6309b70",
  "updated_at": "2026-11-14T00:45:38.628+08:00",
  "audit_ids": [
    "AUD-20261031-029"
  ],
  "dependencies": [
    "INT-001"
  ],
  "read_set": [
    "AGENTS.md",
    "docs/INDEX.md",
    "docs/project/INSTRUCTIONS.md",
    "docs/project/DECISIONS.md",
    "docs/progress/STATUS.md",
    "docs/plans/onboarding-and-auth.md",
    "docs/progress/tasks/AUTH-002.md",
    "docs/plans/IMPLEMENTATION.md",
    "docs/progress/tasks/INT-001.md",
    "docs/progress/tasks/LED-001.md",
    "docs/progress/tasks/LED-003.md",
    "docs/verification/VER-GRP-001.md",
    "docs/verification/VER-GRP-002.md",
    "docs/verification/VER-GRP-003.md",
    "docs/progress/tasks/QA-008.md",
    "test/features/auth_completion_scope_test.dart",
    "docs/progress/tasks/AUTH-003.md",
    "docs/project/USB_TESTING.md"
  ],
  "coverage": [
    "lib/features/auth/**",
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
    "VER-AUTH-002",
    "VER-SEC-004",
    "VER-M1-ACCEPTANCE-REVIEW",
    "VER-QA-008-AUTH"
  ],
  "required_checks": [
    "regression",
    "integration"
  ],
  "acceptance_review": {
    "local_review": "passed",
    "at": "2026-11-01T23:41:43.428Z",
    "commit": "14d1cd6d262e9ce39992e8d3258a358ed318d366",
    "scope": "Acceptance inventory and local regression review only; independent/external acceptance is not established",
    "pending_checks": [
      "integration",
      "integration-review",
      "live-backend"
    ]
  }
}
```

## Scope and acceptance

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-029). Primary owner role: Identity agent.

- Problem: Password recovery and confirmation assistance are missing.
- Impact: Email users can be locked out without recovery.
- Implement: Implement forgot/reset password, expired-link errors and rate-limited confirmation resend.
- Acceptance: Cold/warm valid recovery works; expired/used tokens fail safely; resend obeys service limits.
- Starting point: [source](../../../lib/features/auth/presentation/login_screen.dart).

## Implemented

Current result (2026-11-01T13:24:07.002Z): Existing recovery marker, router priority, cooldown/resend/help/reset forms remain. Recovery password mutation now uses the captured-session non-mutating Auth transport, preventing a late earlier account response from replacing the active GoTrue session user. Weak/same-password errors retain their friendly error contract, successful acknowledgment completes only the initiating recovery session, and PKCE email exchange remains compatible with installed SDK storage.

## Remaining and unverified

Current result (2026-11-01T13:24:07.002Z): Actual valid/expired/used recovery and confirmation email, cold/warm Android/browser callback delivery, provider throttling/SMTP/configuration and persistent platform storage remain unverified. Tests use synthetic sessions with real GoTrue types/exchange over mocked HTTP, not actual email/provider authentication. No deployment/release approval.

## Verification results

Current result (2026-11-01T13:24:07.002Z): [VER-SEC-004](../../verification/VER-SEC-004.md): Final full Flutter suite passed520/520; Dart analysis clean; Android debug APK and JavaScript web builds pass. Fifteen new regressions use installed GoTrue2.27.2 clients with synthetic sessions/HTTP to verify A-response/B-session and same-account relogin isolation, no userUpdated emission, password request token binding, email remaining unchanged until actual SDK PKCE exchange, account change during verifier persistence, inconsistent token/user or foreign/malformed acknowledgment rejection, weak/same-password errors, parallel suppression, timeout/late response and guard recovery, failed verifier storage, slow/obsolete PKCE writer ordering. Focused auth/profile suite passed39/39. No SQL changed or deployed in this batch.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Current result (2026-11-01T13:24:07.002Z): Continue PRO-004/M1 work, then exercise real recovery/confirmation and delayed account-switch mutation on staged accounts/device before closure.

## History

- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-11-01T04:46:22.379Z — Codex root claims password recovery, session-scoped reset and rate-limited confirmation resend; base 16cbdd83a108410be192c5387dbe25c0d6309b70. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-11-01T04:59:23.474Z — Added account-help entry points from login/signup, password-reset requests, confirmation resend and a persistent shared 60-second email-request cooldown. Requests show conditional account-neutral acceptance only after the SDK acknowledges; server rate-limit errors remain actionable. Signup/resend/recovery use the app callback or current web origin. Password recovery events invalidate prior session generations and gate routing to reset before home/profile setup; an encrypted marker binds recovery to the actual account/auth session and restores unfinished flows. Password updates require that recovery session, wait for acknowledgment and discard old-session completions. Drafts clear on session changes. Expired/used/PKCE callback errors reach actionable help, including the installed SDK's URL statusCode convention. All app auth-stream subscriptions now handle errors rather than producing unhandled zone failures.

Remaining: Real email sending, Supabase redirect allowlist/templates/auth policies and exact server rate limits remain unverified. Native cold/warm recovery, expired/used links, PKCE verifier persistence, process death and browser callbacks require real staged/device acceptance. Mocks establish source/state behavior only. SDK PKCE email links must be requested/opened on the same device and newer requests can supersede earlier links. Storage failure during marker cleanup remains a device acceptance case. No backend configuration, live account mutation, deployment or release approval.

Verification: Final full Flutter suite passed 438/438; Dart analysis clean. Focused recovery/assistance/router suite passed 15/15. Fifteen new tests cover marker restart/account separation, stale restore, session claims, installed SDK error shapes, email validation/cooldown/response loss/server limits, reset authorization/acknowledgment/failure/retry, old-account completion, real help/reset widget flows, route priority, expired-link help and draft clearing during a pending reset. Android debug APK builds successfully. No real email or backend account was used. Read the installed Supabase Flutter2.17.2/GoTrue2.27.2 source before wiring callbacks. It stores URL error_code in AuthException.statusCode, and requires onError for each auth subscription; both are handled. Initial focused 12/12 and routing-expanded 14/14 passed. First full suite passed437/437; review added session-change draft clearing and secondary invalid-link visibility, then focused15/15 and final full438/438 passed. Analyzer brace suggestions corrected. Existing package_info_plus KGP warnings remain; physical/link delivery is not inferred from build or injected tests. No live deployment/publication. Next: Continue AUTH-003 per-item profile payment-method outcomes/idempotent retries, then AUTH-004 phone/wallet consent and AUTH-005 accessibility/back handling. Run staged email plus Android/browser cold/warm/expired/used-link acceptance before verified/complete.

- 2026-11-01T13:24:07.002Z — Existing recovery marker, router priority, cooldown/resend/help/reset forms remain. Recovery password mutation now uses the captured-session non-mutating Auth transport, preventing a late earlier account response from replacing the active GoTrue session user. Weak/same-password errors retain their friendly error contract, successful acknowledgment completes only the initiating recovery session, and PKCE email exchange remains compatible with installed SDK storage.

Remaining: Actual valid/expired/used recovery and confirmation email, cold/warm Android/browser callback delivery, provider throttling/SMTP/configuration and persistent platform storage remain unverified. Tests use synthetic sessions with real GoTrue types/exchange over mocked HTTP, not actual email/provider authentication. No deployment/release approval.

Verification: Final full Flutter suite passed520/520; Dart analysis clean; Android debug APK and JavaScript web builds pass. Fifteen new regressions use installed GoTrue2.27.2 clients with synthetic sessions/HTTP to verify A-response/B-session and same-account relogin isolation, no userUpdated emission, password request token binding, email remaining unchanged until actual SDK PKCE exchange, account change during verifier persistence, inconsistent token/user or foreign/malformed acknowledgment rejection, weak/same-password errors, parallel suppression, timeout/late response and guard recovery, failed verifier storage, slow/obsolete PKCE writer ordering. Focused auth/profile suite passed39/39. No SQL changed or deployed in this batch. Installed primary SDK source confirmed that shared updateUser copies its response into the then-current session after awaiting HTTP. The fix bypasses that mutation API rather than relying solely on application post-await guards. An initial expected-token test value was frozen to avoid timestamp-dependent fixtures. Initial analysis found brace-style infos; corrected before clean final checks. Existing Android package_info_plus Kotlin migration and web dependency WASM dry-run warnings remain; debug APK and JavaScript web builds succeed. No live deployment/publication. Next: Continue PRO-004/M1 work, then exercise real recovery/confirmation and delayed account-switch mutation on staged accounts/device before closure.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: integration, integration-review, live-backend. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).

- 2026-11-14T00:45:38.628+08:00 — QA-008 binds login/signup completion to acknowledged SDK Session/generation and mounted lifecycle, checks every continuation and awaits optional onboarding writes. Final15 focused/712 full Flutter, clean analysis and isolated Android debug build62.4s pass. Real provider/native Google/iOS/lifecycle and independent review stay unverified; no signup activation/deployment. State unchanged. See [evidence](../../verification/VER-QA-008-AUTH.md).
