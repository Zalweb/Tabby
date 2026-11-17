# VER-CAP-001

```json verification-metadata
{
  "id": "VER-CAP-001",
  "task_ids": [
    "CAP-001"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "web",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T18:50:46.205Z",
  "tested_commit": "7191d176e643ef8c94401cae5e03718871e32bbd",
  "dirty_tree": true,
  "environment": "Windows; isolated codex/privacy-controls worktree; Flutter/Dart, synthetic widget fixtures and PostgreSQL/WASM with injected JWT subject. No live account mutations or deployment.",
  "commands": [
    "flutter test --no-pub",
    "dart analyze --fatal-infos",
    "node test/web_landing_test.js"
  ]
}
```

## Expected and actual results

Full Flutter suite passed 586/586 and analysis clean. Three new regressions render the actual tab-detail screen with both stored pending and acknowledged expense states, see Recorded rather than claimed consent, retain exact status/balance, and find no unsupported acknowledge/dispute/proposal/custom/recurrence actions in expense details. Landing mirror checks require actual equal/payer-excluded splits and group-history obligations instead of custom-amount/bilateral-transfer claims. The existing website suite passes mirror parity, release simulation and its read-only existing Vercel reachability check; it does not publish the local change or prove the deployed site has this copy.

## Evidence

[Actual widget and landing regressions](../../test/features/capability_exposure_test.dart), [detail copy](../../lib/features/tabs/presentation/tab_detail_screen.dart), [landing](../../landing/index.html), [mirror](../index.html), [capability plan](../plans/missing-capabilities.md). No ledger status serialization or amount arithmetic was changed.

## Limits and next action

Custom splits/tax, recurrence, contact claiming and acknowledgment/proposal/dispute workflows remain CAP-002 through CAP-005 and are not enabled. M1 audited corrections remain CAP-006, whose seeded body incorrectly says M2 while metadata/master plan correctly say M1. Device/end-to-end release acceptance remains unverified; this source copy fix does not complete M1 or those dependent capabilities. No deployment/publication.

- 2026-11-01T18:51:59.682Z ? Active-workspace integration: 16/16 privacy/capability tests passed after copying only nonconflicting owned changes. Project-memory/base-coverage and whitespace checks passed; unrelated terminal work remains present.
