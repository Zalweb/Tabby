# Google entry and introduction implementation

Task: [QA-025](../progress/tasks/QA-025.md). Product decision: [DEC-013](../project/DECISIONS.md#dec-013--google-only-entry-and-post-authentication-introduction). User explicitly asked to implement this design and then continued it; no additional design approval is needed for the same scope.

## Design

Use the existing Flutter/Supabase Google OAuth flow and current immutable account identity. A single warm cream/amber welcome screen has one Google action beneath a large generated transparent Tabby. Text and controls remain native. After verified Google authentication, query the actor's real profile; completed registrations go home. Incomplete profiles see three calm mascot-led pages about shared expenses, bilateral tabs and external-payment/recipient-confirmation. Required name/mobile and optional receiving details follow. Store introduction acknowledgment in encrypted account-scoped local storage; completed server profiles skip introduction on another device. A failed/unknown profile check blocks navigation with a retry, never silently treating unknown as registered. Session generations guard every asynchronous result.

The user selected Google-only entry over the previous email/Google form and pre-login tutorial. Reusing the screenshot as a single full-screen bitmap would prevent accessible text/actions, so consume separate generated character assets. Reference images guide spacing/hierarchy only; unsupported chat, AI receipt extraction, budgets and automation claims are excluded.

## Implementation sequence

1. Preserve OAuth browser/native/callback guards while removing email/password/signup/offline/Apple entry UI. Redirect old signup and unauthenticated introduction links to Google welcome. Retain authenticated legacy recovery deep links so existing recovery sessions are not corrupted.
2. Introduce a shared session-scoped registration check and retry screen. Reuse it in restored-session, OAuth listener and native completion paths; de-duplicate overlapping same-generation checks.
3. Build the minimal three-page post-authentication introduction with progress/back/skip, account-scoped acknowledgment and storage-failure retry. Constrain profile/optional receiving setup; remove decorative avatar/icon choices and prioritize generated mascot art.
4. Prepare/test a narrowly scoped server configuration operator: enable registrations while disabling email/phone/anonymous/other OAuth providers, retaining only the existing Google provider and credentials. Encrypt and verify rollback backup; preserve existing users/sessions/ledger/hooks. Persist the policy for later configuration runs. Apply only after tests/review and verify health/public settings and rejected disabled entry probes without creating real accounts.
5. Update meaningful routing, session-concurrency, profile failure, account-switch, acknowledgment and accessibility tests. Preserve backend and legacy recovery tests. Run focused/full checks and analysis, inspect phone/tablet rendered previews, then signed build/identity/alignment and in-place tablet upgrade. Do not sign out the owner or clear data to inspect login.
6. Save prompts/provenance, exact candidate/source hashes and sanitized verification; refresh status/plain/base checks and report unresolved external/device/review gates honestly.

## Validation

Explicit cases: first login vs completed profile; missing/error lookup; repeated callbacks; late response after signout/another account/same-account relogin; intro write failure; interrupted setup/restart; back/skip; unauthenticated deep links; phone/tablet/landscape/200% text; reduced motion; exact installed APK digest/certificate/version. Real first-time Google creation requires a new consented Google identity and is not inferred from synthetic or existing-account tests.
