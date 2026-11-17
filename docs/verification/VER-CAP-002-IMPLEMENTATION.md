# VER-CAP-002-IMPLEMENTATION

```json verification-metadata
{
  "id": "VER-CAP-002-IMPLEMENTATION",
  "task_ids": [
    "CAP-002",
    "GRP-002",
    "QA-001"
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
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "documentation",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "live-backend",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-02T00:03:20.851Z",
  "tested_commit": "1e4bdb6a8981705b26a9cc61526f43fd915192f1",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8. Source and local fixtures only; no attached Android device or live backend.",
  "commands": [
    "flutter analyze --no-pub lib test scripts",
    "flutter test --no-pub",
    "node scripts/test-money-commands.cjs",
    "node scripts/test-backend-native.cjs",
    "node --test scripts/check-project-memory.test.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 1e4bdb6a8981705b26a9cc61526f43fd915192f1",
    "git diff --check"
  ]
}
```

## Expected and actual results

Flutter analysis of lib/test/scripts passed; full suite636/636 passed. Eight custom calculator/durable queue/form regressions cover integer charge parity, odd cents, zero shares, permutation/ties, overflow/invalid inputs, session/intent isolation, explicit retry, unreadable drafts and truthful offline UI. PostgreSQL/WASM and native PostgreSQL17.11 behavior passed, including default rollout denial, owner/outsider isolation, stored components, replay/conflict, group payer choices and inactive-roster denial for M1/M2. Eight independent native sessions created exactly one charged expense; changed intent rejected. Existing financial/social/correction races still pass. Memory-tool tests8/8 pass, including latest-evidence and open-gate protection. Initial style/const-map/test-scroll findings were corrected before final runs.

## Evidence

Implemented hidden custom-split form and strict integer calculator, independent base tax/service basis points, half-up rounding, largest-remainder per-party allocation and exact stored SQL breakdown. New create_expense_v3 independently recalculates and validates final shares. Both application constants and server rollout flags default false. M2 joins the existing durable replay owner/actor-operation registry with session-scoped results, immutable intent, explicit retry, attention truth and failed-draft recovery that cannot silently mint a new financial intent. New roster validation also protects fresh M1 expense commands against persistent membership for a member who left; historical/approved compensating entries remain unchanged.

Ignored .dart_tool/cap002-final-{analysis,tests}.log, cap002-native.log and cap002-memory.log. Native PostgreSQL is a source-subset fixture with injected Auth, not deployed Supabase. Historical task seed paragraphs are superseded by this dated checkpoint.

## Limits and next action

Integration/live Supabase, full provisioning/upgrade and physical-device acceptance remain unverified; M1 LED-003/PAY-001 dependencies remain implemented, not complete. Both rollout gates remain false; no public M2 feature or deployment claimed. Independent acceptance/review is still required. Next: Run live/dependency/integrated acceptance before enabling either flag; continue CAP-003 under the frozen hidden M2 contracts.
