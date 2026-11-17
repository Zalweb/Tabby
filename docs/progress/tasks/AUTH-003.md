# AUTH-003 — Profile completion ignores failed method saves

```json task-metadata
{
  "id": "AUTH-003",
  "area": "onboarding-and-auth",
  "title": "Profile completion ignores failed method saves",
  "milestone": "M1",
  "priority": "P2",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "d57935926e2720300e5758cb91028b92e12570e0",
  "updated_at": "2026-11-14T00:45:38.628+08:00",
  "audit_ids": [
    "AUD-20261031-030"
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
    "docs/progress/tasks/AUTH-003.md",
    "docs/plans/IMPLEMENTATION.md",
    "docs/progress/tasks/INT-001.md",
    "docs/progress/tasks/LED-001.md",
    "docs/progress/tasks/LED-003.md",
    "docs/verification/VER-GRP-001.md",
    "docs/verification/VER-GRP-002.md",
    "docs/verification/VER-GRP-003.md",
    "docs/progress/tasks/QA-008.md",
    "test/features/auth_completion_scope_test.dart",
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
    "VER-AUTH-003",
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

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-030). Primary owner role: Identity agent.

- Problem: Profile completion ignores failed method saves.
- Impact: Users leave setup believing unsaved QR methods are available.
- Implement: Track per-item save results; preserve drafts and retry failed methods idempotently before reporting completion.
- Acceptance: One upload fails among multiple methods; saved items do not duplicate and failure remains actionable.
- Starting point: [source](../../../lib/features/auth/presentation/complete_profile_screen.dart).

## Implemented

Current result (2026-11-01T05:29:31.732Z): Profile setup persists owned account-scoped drafts, QR bytes, stable method/operation IDs, preference intent and per-item save outcomes before transport. Acknowledged methods are skipped on retries; uncertain responses replay the frozen command. Failure keeps setup open with per-item errors and retry. Explicit continue-without-unsaved retains a deferred draft, resumable from payment-method management. Startup honors required pending setup even after profile fields were saved. Profile metadata changes no longer recreate preferences/unmount the setup form; actual account/session changes reset the route and discard stale results. The setup editor now stages a clearly labelled draft through the shared QR validator.

## Remaining and unverified

Current result (2026-11-01T05:29:31.732Z): Full Supabase profile API/RLS/HTTP, response loss through real SDK, cross-device setup, Android secure-storage/large images/process death/picker recovery remain unverified. Drafts are local encrypted state; another device does not restore these unsaved QR bytes. Storage scale/cleanup remains AND-004/SEC-005; picker/back recovery remains AND-003/AUTH-005. No migration deployed or release approval.

## Verification results

Current result (2026-11-01T05:29:31.732Z): [VER-AUTH-003](../../verification/VER-AUTH-003.md): Final full Flutter suite passed451/451; Dart analysis clean. Focused setup/model suite passed14/14 before final full verification. Thirteen new model/provider/widget regressions cover partial success, restart/response-loss stable retries, owned immutable bytes/account isolation, persistence failure, preference rollback/promotion, reentrant writes, deferred resume, corrupt draft retention, disposed/session-changed results, metadata provider lifetime and same-account auth revisions. The existing setup widget regression now asserts no automatic GCash, no account-number QR generator, explicit receiving confirmation and honest failed-save state. Android debug APK builds. Native PostgreSQL17.11 and PostgreSQL/WASM subsets pass phone canonicalization/uniqueness/availability alongside existing financial/QR/push contracts. Eight native owner-role equivalent-format writes admit exactly one canonical phone.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Current result (2026-11-01T05:29:31.732Z): Continue AUTH-005 accessibility/back behavior, then remaining dependency-ready M1 tasks. Exercise partial-upload failure/retry/restart and deferred resume against staged accounts/device before verified/complete.

## History

- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-11-01T04:59:33.428Z — Codex root claims per-method setup save results, retained drafts and idempotent retry before completion; base d57935926e2720300e5758cb91028b92e12570e0. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-11-01T05:29:31.732Z — Profile setup persists owned account-scoped drafts, QR bytes, stable method/operation IDs, preference intent and per-item save outcomes before transport. Acknowledged methods are skipped on retries; uncertain responses replay the frozen command. Failure keeps setup open with per-item errors and retry. Explicit continue-without-unsaved retains a deferred draft, resumable from payment-method management. Startup honors required pending setup even after profile fields were saved. Profile metadata changes no longer recreate preferences/unmount the setup form; actual account/session changes reset the route and discard stale results. The setup editor now stages a clearly labelled draft through the shared QR validator.

Remaining: Full Supabase profile API/RLS/HTTP, response loss through real SDK, cross-device setup, Android secure-storage/large images/process death/picker recovery remain unverified. Drafts are local encrypted state; another device does not restore these unsaved QR bytes. Storage scale/cleanup remains AND-004/SEC-005; picker/back recovery remains AND-003/AUTH-005. No migration deployed or release approval.

Verification: Final full Flutter suite passed451/451; Dart analysis clean. Focused setup/model suite passed14/14 before final full verification. Thirteen new model/provider/widget regressions cover partial success, restart/response-loss stable retries, owned immutable bytes/account isolation, persistence failure, preference rollback/promotion, reentrant writes, deferred resume, corrupt draft retention, disposed/session-changed results, metadata provider lifetime and same-account auth revisions. The existing setup widget regression now asserts no automatic GCash, no account-number QR generator, explicit receiving confirmation and honest failed-save state. Android debug APK builds. Native PostgreSQL17.11 and PostgreSQL/WASM subsets pass phone canonicalization/uniqueness/availability alongside existing financial/QR/push contracts. Eight native owner-role equivalent-format writes admit exactly one canonical phone. Initial transform anchors encountered CRLF/indentation differences and an orphaned old helper body; corrected before passing analysis. Initial widget expectation exposed that whole-profile watching recreated the security provider and unmounted setup; changed to account-ID selection plus explicit auth-session revision, with regressions. Initial phone role fixture lacked Supabase API table grants and exposed that full profile RLS is not in this financial subset; trigger tests are explicitly owner-role rather than fabricating app authorization, while availability RPCs use actual authenticated/anon roles. The anonymous fixture also cleared its synthetic JWT subject before role switching. Initial full450/450 passed, then same-account revision coverage produced final451/451. Existing package_info_plus KGP warning remains. No source/unit/build result is device or deployment evidence. No live deployment/publication. Next: Continue AUTH-005 accessibility/back behavior, then remaining dependency-ready M1 tasks. Exercise partial-upload failure/retry/restart and deferred resume against staged accounts/device before verified/complete.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: integration, integration-review, live-backend. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).

- 2026-11-14T00:45:38.628+08:00 — QA-008 binds login/signup completion to acknowledged SDK Session/generation and mounted lifecycle, checks every continuation and awaits optional onboarding writes. Final15 focused/712 full Flutter, clean analysis and isolated Android debug build62.4s pass. Real provider/native Google/iOS/lifecycle and independent review stay unverified; no signup activation/deployment. State unchanged. See [evidence](../../verification/VER-QA-008-AUTH.md).
