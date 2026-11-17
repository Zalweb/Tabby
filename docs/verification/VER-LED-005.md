# VER-LED-005 — Explicit contact financial parties

```json verification-metadata
{
  "id": "VER-LED-005",
  "task_ids": [
    "LED-001",
    "LED-005"
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
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T13:31:47.752Z",
  "tested_commit": "f6ff659a356ecde5a22109bb84c2ee375f205698",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; PGlite 0.5.14 / PostgreSQL 18.6 WASM, financial migration subset and injected JWT subject/roles.",
  "commands": [
    "flutter test",
    "dart analyze --fatal-infos",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base f6ff659a356ecde5a22109bb84c2ee375f205698",
    "git diff --check"
  ]
}
```

## Expected and actual results

Flutter 280/280 passed; analysis no issues. SQL harness with real financial source functions passed: two same-name contacts get different tabs; same contact replay reuses its tab; registered-ID collisions and other-owner resolution denied; contact pays or owes; incoming/outgoing partial cash records retain actual parties, reduce the correct balance and replay once; changed payload and overpayment denied; authenticated balance RPC agrees. Client tests cover PartyRef serialization, local UUID tab markers, cache reload and actual contact payer parsing.

## Evidence

Expanded scripts/test-money-commands.cjs applies additive 20261031000003_contact_financial_parties.sql after the existing financial migration subset. Output MONEY_COMMAND_CONTRACT_OK under PostgreSQL 18.6/PGlite 0.5.14. Flutter mocks exercise storage and UI; these are not device tests. Initial generated SQL dollar quoting and test binding setup failures were corrected before final passing checks; four old E2E expectations were updated for cash-only unregistered contacts and warning-only similarity detection.

## Limits and next action

Full Supabase migration inventory, independent-session concurrency, real RPC/network response loss, deployed grants and actual device restart remain unverified. Legacy ambiguously merged history is not repaired by similarity. This private contact cash record is owner-attested ledger history, not a claim that an unregistered person verified a wallet payment. No migration deployed, app installed or release published. Run staging upgrade and authenticated-role/device acceptance before marking complete.
