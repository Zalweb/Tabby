# onboarding-and-auth implementation plan

## Purpose and current state

Recoverable startup, account recovery, profile setup and accessible onboarding. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Identity agent**.

## Target behavior and contracts

Startup renders before remote work. Separate storage, notification, auth and profile errors. Recovery links support cold/warm starts and expired tokens. Save setup outcomes per item; retries do not duplicate methods. Normalize Philippine phones to one canonical form. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

AUTH-001 implementation checkpoint (2026-10-31): main renders StartupGate first. Optional preference, notification and profile errors offer continue/retry; authentication initialization errors offer retry. Startup retries reuse initialized Supabase and install one auth listener. Unit/widget evidence does not establish real plugin failure recovery or offline device startup; those remain unverified in the task record.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [AUTH-001](../progress/tasks/AUTH-001.md) — Startup errors can block authentication initialization | P1 | Storage exception, notification exception and offline profile fetch each show recoverable UI. |
| [AUTH-002](../progress/tasks/AUTH-002.md) — Password recovery and confirmation assistance are missing | P2 | Cold/warm valid recovery works; expired/used tokens fail safely; resend obeys service limits. |
| [AUTH-003](../progress/tasks/AUTH-003.md) — Profile completion ignores failed method saves | P2 | One upload fails among multiple methods; saved items do not duplicate and failure remains actionable. |
| [AUTH-004](../progress/tasks/AUTH-004.md) — Phone validation and default wallet assumptions are weak | P2 | 09/+639/639 equivalents normalize identically; invalid prefixes fail; profile phone does not automatically enable GCash. |
| [AUTH-005](../progress/tasks/AUTH-005.md) — Onboarding accessibility and back behavior need validation | P2 | Small/landscape/200 percent text screens remain usable; back follows steps then exits normally. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Password recovery and confirmation assistance checkpoint 2026-11-01T04:59:23.474Z

Recovery requires a verified SDK passwordRecovery event or an encrypted pending marker for the exact restored auth session. Recovery routing precedes profile/home; ordinary sessions cannot use reset. Password writes and UI completion are session scoped, and draft passwords clear on account/session change. Email recovery/confirmation requests use a shared persisted local60-second interval plus authoritative server limits, with conditional acceptance copy only after acknowledgment. Configure io.supabase.tabby://login-callback and the intended web origin in staged auth allowlists/templates, then verify same-device PKCE cold/warm/expired/used flows before closure. No auth links or tokens are stored in project memory.

See [verification](../verification/VER-AUTH-002.md). No deployment; environment-specific limits remain open.

## Durable profile setup and canonical mobile details checkpoint 2026-11-01T05:29:31.732Z

Receiving-method setup is an account-scoped durable draft until each selected method receives its original server ID or the user explicitly defers unsaved items. Retries preserve frozen operation/method IDs and skip acknowledged rows; setup never reports unsaved methods available. Deferred items remain resumable from method management. Profile phone and wallet destination are independent: normalize supported Philippine mobile forms, reject malformed/new duplicate writes, and require explicit receiving-detail confirmation rather than inventing GCash from a profile phone. Existing legacy collisions are retained, not automatically rewritten. Auth/session changes recreate account forms; ordinary profile metadata edits preserve the current security/preferences provider.

See [verification](../verification/VER-AUTH-003.md). No deployment; environment-specific limits remain open.

## Adaptive onboarding and truthful draft navigation checkpoint 2026-11-01T05:52:45.134Z

Onboarding back moves through slides; setup back moves through steps. Only unsaved edits prompt. Explicit save-and-leave waits for retained local setup persistence. At 200 percent text actions remain scroll-reachable, labels wrap and fixed-height buttons no longer truncate.

See [verification](../verification/VER-AUTH-005.md). No deployment; environment-specific limits remain open.

## Session-bound credential completion checkpoint 2026-11-14T00:45:38.628+08:00

A successful login/signup acknowledgment first waits for the public SDK auth event and requires the exact active Session object before capturing generation. After preference/profile/ledger/profile-check awaits, obsolete or disposed forms cannot change global auth/profile gates or navigate. Optional onboarding write errors are awaited/caught; mounted busy state always clears. [QA-008](../verification/VER-QA-008-AUTH.md) records15 focused/712 full regressions, clean analysis and debug packaging; actual provider/native lifecycle and review remain open. Signup rollout stays unchanged.

## Google browser handoff checkpoint 2026-11-17T06:55:25.371Z

Google OAuth returns explicit authenticated/browserOpened/cancelled results. Browser launch shows neutral pending instructions; only the acknowledged current Session completes native login. Scoped callback error observation stops on disposal or later-session change, and missing native tokens fall back once. Reviewed Azure callback/existing-client credential repair now passes manual real Google Home/new server-session acceptance. [QA-022 evidence](../verification/VER-QA-022-GOOGLE.md) records29 focused,48 physical fixture and759 integrated regressions. These do not replace independent review or remaining production/provider lifecycle checks.


## Google-only registration checkpoint 2026-11-17T07:49:02.066Z

The explicit user directive and DEC-013 supersede pre-login tutorial/email-entry requirements. Google-only welcome→real server profile check→account-specific introduction→required profile→Home is implemented. Complete profiles bypass introduction; incomplete profiles resume using an encrypted per-account marker; unknown checks retry without entering Home. Required profile fields and optional receiving methods preserve durable save/session guards. Auth-only server policy now permits Google registration and rejects other providers, with recovery backup verified. Legacy recovery deep links remain compatible. [QA-025 evidence](../verification/VER-QA-025-GOOGLE-ENTRY.md) records776 host regressions,3 isolated native cases and in-place signed tablet+13. Actual brand-new Google consent/creation/profile completion and independent review remain open; no public release implied.


## App-wide warm presentation — 2026-11-17T08:16:51.570Z

The current user directive/DEC-014 extends welcome/introduction cream, amber and charcoal across this area's screens and overlays, with matching dark mode. [Current design authority](../project/DESIGN.md) and [QA-026](../progress/tasks/QA-026.md) supersede former mint/emerald presentation only. Existing behavior, financial meaning, native QR/image colors and session/durable-save guards remain. Verification must distinguish UI fixtures from actual provider/backend/device acceptance.

2026-11-17T14:30:25.234Z - QA-031 WelcomeMascot delegates to the shared animation engine. Login shows welcome, pending Google/loading/browser handoff shows waiting, callback failure helpful. Intro welcome/notebook keep clean existing art and pause/motion preferences. No OAuth/registration contract change. [Mascot plan](situation-mascot-animation.md).

## First-use mascot introduction - 2026-11-19T14:16:50+08:00

The owner directed that the introduction appear on fresh signed-out launches before the existing Google welcome. Its completion belongs to the installation. Restored authenticated accounts bypass it. An unfinished authenticated profile proceeds directly to required setup and retains retry on unknown server status. The cold-start animation honors reduced motion and releases real initialization errors promptly. This supersedes the introduction order in the 2026-11-17 checkpoint. [Task](../progress/tasks/QA-051.md) and [verification](../verification/VER-QA-051-FIRST-LAUNCH.md).
