# VER-LED-006 — Truthful sync state and safe retry

```json verification-metadata
{
  "id": "VER-LED-006",
  "task_ids": [
    "LED-001",
    "LED-004",
    "LED-006"
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
      "category": "backend-integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T13:42:59.823Z",
  "tested_commit": "c286e7972cb4128b831c2449130e27d3b5e6c208",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; unit/widget injected connectivity, secure-storage and sync callbacks. No live backend/device outage simulation.",
  "commands": [
    "flutter test",
    "dart analyze --fatal-infos",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base c286e7972cb4128b831c2449130e27d3b5e6c208",
    "git diff --check"
  ]
}
```

## Expected and actual results

288/288 Flutter tests passed; analysis clean. Regressions verify online does not imply synced, failed refresh retains prior successful timestamp, pending/attention counts prevent success, local saves have no server timestamp, callback exceptions are actionable, concurrent sync invokes one callback, manual retry preserves wire IDs/payload and unreadable queue cannot be overwritten or counted as empty. Profile UI explicitly injects offline connectivity and verifies local-only outcome.

## Evidence

Structured SyncReport is consumed by diagnostics and the same dashboard refresh path. Ledger fetch and per-tab balance errors now propagate; no successful empty read is fabricated from an exception. A remaining name-based suppression branch was found and replaced with the shared immutable predicate. First broad run had 287 passed and one UI timing assertion failure; focused injected-probe test and final 288/288 run passed.

## Limits and next action

These are unit/widget/cache regressions, not actual backend outage or device evidence. Pending legacy identities remain held for review. Session-generation account isolation remains SEC-004. No migration/deployment/publication performed. Next: security gate/session isolation and dependency-ready application tasks.
