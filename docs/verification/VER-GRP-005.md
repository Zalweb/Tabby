# VER-GRP-005 — Strict PHP input and amount limits

```json verification-metadata
{
  "id": "VER-GRP-005",
  "task_ids": [
    "GRP-005"
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
    }
  ],
  "timestamp": "2026-10-31T14:25:55.961Z",
  "tested_commit": "3697c859620beeee9be70914d45f8546370425ea",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; widget/native storage mocks; native PostgreSQL 17.11 and PGlite financial/group migration subset with injected JWT subjects and authenticated roles.",
  "commands": [
    "flutter test",
    "flutter test test/core/currency_formatter_test.dart test/features/create_tab_flow_test.dart test/features/e2e_all_screens_buttons_test.dart",
    "dart analyze --fatal-infos",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full Flutter suite 324/324; Dart analysis clean. Native PostgreSQL 17.11 and PGlite source contracts accept maximum amount exactly, reject one-cent overflow and noninteger centavo payloads; group atomicity and replay concurrency continue to pass.

## Evidence

[Parser regressions](../../test/core/currency_formatter_test.dart) reject abc.50, exponent notation, malformed grouping, excess precision and huge overflow; exact PHP maximum and formatted values roundtrip. [Form regressions](../../test/features/create_tab_flow_test.dart) repeatedly submit invalid amounts, assert inline field errors and no financial entries, then accept PHP 1,250.50 as 125050 centavos. Payment regression verifies malformed input never invokes the durable write. [Actual SQL harness](../../scripts/test-money-commands.cjs) exercises the source CHECK limits and integer casts.

## Limits and next action

Migration 20261031000005_money_amount_limits.sql is present in schema_all.sql and tested on local source subset only. Existing historical data inventory and live Supabase grants/upgrade behavior remain unverified. Real Android keyboard and accessibility acceptance remains open. No deployment/publication.
