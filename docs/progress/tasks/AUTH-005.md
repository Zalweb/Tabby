# AUTH-005 — Onboarding accessibility and back behavior need validation

```json task-metadata
{
  "id": "AUTH-005",
  "area": "onboarding-and-auth",
  "title": "Onboarding accessibility and back behavior need validation",
  "milestone": "M1",
  "priority": "P2",
  "status": "implemented",
  "owner": "Codex root",
  "platform": "Codex desktop / Windows",
  "branch": "codex/m1-application-fixes",
  "base_commit": "dd6728a548ad76dab16883bb551b997c5be35698",
  "updated_at": "2026-11-01T23:41:43.428Z",
  "audit_ids": [
    "AUD-20261031-032"
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
    "docs/progress/tasks/AUTH-005.md",
    "docs/plans/IMPLEMENTATION.md",
    "docs/progress/tasks/INT-001.md",
    "docs/progress/tasks/LED-001.md",
    "docs/progress/tasks/LED-003.md",
    "docs/verification/VER-GRP-001.md",
    "docs/verification/VER-GRP-002.md",
    "docs/verification/VER-GRP-003.md"
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
    "VER-AUTH-005",
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

[Audit finding](../../audits/2026-10-31-android-review.md#aud-20261031-032). Primary owner role: Identity agent.

- Problem: Onboarding accessibility and back behavior need validation.
- Impact: Fixed slides and default back can overflow or exit unexpectedly.
- Implement: Make slides scroll/adapt; system back returns to previous slide/step and prompts only for unsaved edits.
- Acceptance: Small/landscape/200 percent text screens remain usable; back follows steps then exits normally.
- Starting point: [source](../../../lib/features/onboarding/presentation/onboarding_screen.dart).

## Implemented

Current result (2026-11-01T05:52:45.134Z): Onboarding adapts to small portrait, landscape and 200 percent text with scrollable slides and reachable actions; hardware back visits the previous slide. Setup returns to its previous step and prompts only for dirty identity edits, preserving the encrypted draft before leaving. Staged receiving-method and signup forms protect unsaved edits. Shared buttons wrap text and grow; pending auth forms disable edits. Controllers are disposed and repeated navigation is guarded.

## Remaining and unverified

Current result (2026-11-01T05:52:45.134Z): Actual Android gesture/system back, screen-reader, keyboard, process death and physical 200 percent text journeys remain unverified. Widget platform-pop interception is not a device exit test. Existing web WASM dry-run dependency warnings and Android package_info_plus Kotlin migration warning remain; JavaScript web and debug APK builds pass. No deployment or release approval.

## Verification results

Current result (2026-11-01T05:52:45.134Z): [VER-AUTH-005](../../verification/VER-AUTH-005.md): Full Flutter suite passed 465/465; final focused accessibility/back suite passed 14/14, including retained-draft save before platform exit. Dart analysis clean. Android debug APK and JavaScript web builds succeeded. Initial dirty-editor dialog overflow at 200 percent text was reproduced and fixed by making dialogs scrollable; initial semantics fixture teardown ordering was corrected. Native/device/backend integration was not exercised for this UI batch.

## Deployment

Not deployed. Use additive migrations, test fresh and upgraded databases, and update schema_all.sql together. No production mutation is authorized by this task record alone.

## Handoff

Current result (2026-11-01T05:52:45.134Z): Continue PRO-001 profile persistence and remaining dependency-ready M1 tasks. Run physical Android navigation/accessibility and process-death acceptance before verified/complete.

## History

- 2026-10-31T12:13:06.279Z — Seeded from the approved implementation plan; no remediation claimed.

- 2026-11-01T05:29:49.373Z — Codex root claims adaptive onboarding/auth layouts, system back and retained setup drafts; base dd6728a548ad76dab16883bb551b997c5be35698. Mandatory docs, area plan/task, dependencies, referenced evidence and current source rechecked; no competing claims. Integration owner reserves listed shared files. No deployment/publication.

- 2026-11-01T05:52:45.134Z — Onboarding adapts to small portrait, landscape and 200 percent text with scrollable slides and reachable actions; hardware back visits the previous slide. Setup returns to its previous step and prompts only for dirty identity edits, preserving the encrypted draft before leaving. Staged receiving-method and signup forms protect unsaved edits. Shared buttons wrap text and grow; pending auth forms disable edits. Controllers are disposed and repeated navigation is guarded.

Remaining: Actual Android gesture/system back, screen-reader, keyboard, process death and physical 200 percent text journeys remain unverified. Widget platform-pop interception is not a device exit test. Existing web WASM dry-run dependency warnings and Android package_info_plus Kotlin migration warning remain; JavaScript web and debug APK builds pass. No deployment or release approval.

Verification: Full Flutter suite passed 465/465; final focused accessibility/back suite passed 14/14, including retained-draft save before platform exit. Dart analysis clean. Android debug APK and JavaScript web builds succeeded. Initial dirty-editor dialog overflow at 200 percent text was reproduced and fixed by making dialogs scrollable; initial semantics fixture teardown ordering was corrected. Native/device/backend integration was not exercised for this UI batch.  No live deployment/publication. Next: Continue PRO-001 profile persistence and remaining dependency-ready M1 tasks. Run physical Android navigation/accessibility and process-death acceptance before verified/complete.

- 2026-11-01T14:47:49.305Z ? Superseding draft-source checkpoint: AND-003 now implements encrypted form retention and attributed lost-image recovery for the relevant avatar/method/profile/entry surfaces; see [VER-AND-003](../../verification/VER-AND-003.md). Prior native process-death and device lifecycle checks remain unverified; route/LostData fixtures do not close them.

- 2026-11-01T23:41:43.428Z ? M1 acceptance reconciliation at 14d1cd6d262e9ce39992e8d3258a358ed318d366: current acceptance and linked evidence reviewed against fresh local Flutter628/628, clean scoped Flutter analysis and native PostgreSQL source/concurrency suites. This closes only the local regression review. Still unverified: integration, integration-review, live-backend. Keep status implemented; no real hardware or authenticated Supabase project was tested. Next: run the named environment/integration checks, then independent acceptance review. See [review matrix](../../verification/VER-M1-ACCEPTANCE-REVIEW.md).
