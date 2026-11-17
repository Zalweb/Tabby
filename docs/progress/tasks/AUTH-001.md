# AUTH-001 — Startup errors can block authentication initialization

```json task-metadata
{
  "id": "AUTH-001",
  "area": "onboarding-and-auth",
  "title": "Startup errors can block authentication initialization",
  "milestone": "M1",
  "priority": "P1",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "d33d716a52461ce70c4f086bb20f4c68f3bd58d6",
  "updated_at": "2026-11-01T23:41:43.428Z",
  "audit_ids": [
    "AUD-20261031-028"
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
    "docs/progress/tasks/AUTH-001.md",
    "docs/progress/tasks/INT-001.md",
    "docs/verification/README.md"
  ],
  "coverage": [
    "lib/features/auth/**",
    "test/**",
    "supabase/**",
    "lib/core/**",
    "pubspec.yaml",
    "pubspec.lock",
    "lib/main.dart",
    "docs/**"
  ],
  "verification": [
    "VER-M1-001",
    "VER-M1-ACCEPTANCE-REVIEW"
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

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-028). Primary owner role: Identity agent.

- Problem: Startup errors can block authentication initialization.
- Impact: Storage or notification failure can prevent usable startup.
- Implement: Render startup state first; isolate initializers with retry and nonfatal service failures.
- Acceptance: Storage exception, notification exception and offline profile fetch each show recoverable UI.
- Starting point: [source](../../../lib/main.dart).

## Implemented

Current update (2026-10-31T13:02:47.513Z): Startup renders loading UI before service completion, isolates optional storage/notification failures, provides retry on auth failure and continue/retry on optional failures, bounds optional reads/profile lookup waits and avoids duplicate auth listeners on retry. Widget regressions cover failed auth retry and optional failure continuation.

No application changes implemented. This task is a planned audit/capability item.

## Remaining and unverified

Current update (2026-10-31T13:02:47.513Z): Tests inject gate outcomes; real plugin failure/offline Supabase integration and device cold launch remain unverified. Same-account session-generation race remains in SEC-004.

Implementation, regression tests and integration checks remain. Device/backend evidence must be recorded when relevant; baseline passing tests do not close this task. Confirm the current implementation before editing; record any finding disproved with evidence.

## Verification results

Final local results (2026-10-31T13:05:10.357Z): Final full Flutter suite passed 261/261; direct Dart analysis with --fatal-infos passed with no issues. Android debug APK packaging succeeded (assembleDebug 226.1 seconds), with existing Java native-access/source-8 and package_info_plus Kotlin-plugin warnings. Build ran during iterative source fixes: it verifies native resource packaging, not an exact release candidate. Documentation regression 5/5 and base change-coverage validation passed. No device/live-backend checks or deployment performed.

Current update (2026-10-31T13:02:47.513Z): Current result: see [VER-M1-001](../../verification/VER-M1-001.md); source/unit/widget evidence only unless explicitly stated.

Not run for this task. Run the acceptance scenario above plus affected Flutter tests; SQL/security work requires authenticated-role database checks. Android behavior requires device evidence. Link results using the verification template.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Read dependencies and area plan; claim ownership and file reservations; reproduce the issue; add a regression; implement; verify and update this record. Shared provider/model/schema/workflow edits require the integration owner.

## History

- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-10-31T12:57:54.906Z — Codex root claims startup gate/main initialization and widget regression. Read onboarding plan, task, INT-001 and current main/config/router. Integration-owner reservation; other claims rechecked.

### 2026-10-31T13:02:47.513Z — implementation review

Startup renders loading UI before service completion, isolates optional storage/notification failures, provides retry on auth failure and continue/retry on optional failures, bounds optional reads/profile lookup waits and avoids duplicate auth listeners on retry. Widget regressions cover failed auth retry and optional failure continuation.

Remaining: Tests inject gate outcomes; real plugin failure/offline Supabase integration and device cold launch remain unverified. Same-account session-generation race remains in SEC-004.

Verification history: first full suite had 251 passes and four expectations of fuzzy merging failed; expectations corrected to approved invariant. Next full suite passed 257/257. Startup suite initially found an unhandled deferred-future failure; corrected scheduling with Future.sync, focused startup suite passed 4/4. One analyzer const suggestion corrected. Documentation validator tests initially failed without Git in PATH; rerun passed 5/5. No deployment/publication. Next: LED-003 durable executor/server idempotency, LED-001 contact identity mapping, and listed integration checks; continue other dependency-ready M1 work.

- 2026-10-31T13:05:10.357Z — Final full Flutter suite passed 261/261; direct Dart analysis with --fatal-infos passed with no issues. Android debug APK packaging succeeded (assembleDebug 226.1 seconds), with existing Java native-access/source-8 and package_info_plus Kotlin-plugin warnings. Build ran during iterative source fixes: it verifies native resource packaging, not an exact release candidate. Documentation regression 5/5 and base change-coverage validation passed. No device/live-backend checks or deployment performed. Git status inspected; prior M0 changes preserved. Build-generated android/.kotlin sessions are ignored, no generated files staged. Next available foundational work is LED-003 server idempotency and executor mapping; do not treat current conservative reconciliation as duplicate-write prevention.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: integration, integration-review, live-backend. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).
