# VER-QR-002 — Exact-object method access

```json verification-metadata
{
  "id": "VER-QR-002",
  "task_ids": [
    "QR-002"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "backend-authorization",
      "outcome": "passed"
    },
    {
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T18:50:28.229Z",
  "tested_commit": "36d630b8da722c4b7b49555edd34aa5366fcfcc6",
  "dirty_tree": true,
  "environment": "Native PostgreSQL 17.11 and PGlite, unmodified source migration subset, injected auth.uid/roles, minimal synthetic storage.objects/buckets fixtures. Windows Flutter source authorization tests. No Supabase HTTP or device.",
  "commands": [
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "flutter test test/features/authorization_hardening_test.dart",
    "node --test scripts/check-project-memory.test.cjs",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Native PostgreSQL 17.11 and PGlite passed source-policy authorization matrix: owner/friend/actual zero-aggregate group debtor allowed; uninvolved group member, pending friend, stranger, anonymous, unbound and guessed paths denied. Settlement/inactivation remove new debtor/friend access as appropriate. Existing financial/group/receipt/race contracts pass. Flutter authorization regressions and documentation tooling tests passed.

## Evidence

[Role acceptance](../../scripts/test-payment-method-access.cjs) uses six synthetic identities, group membership and actual financial commands to establish pair debts independently of aggregate balances. It reads actual RLS-protected method/object rows under authenticated/anonymous roles. [Migration](../../supabase/migrations/20261101000003_payment_method_access.sql) replaces the old owner-row subquery policy with narrow SECURITY DEFINER authorization and replaces individual-only tab listing.

## Limits and next action

Local source-policy acceptance is not deployed authorization inventory or Storage HTTP evidence. Source not deployed; URL expiry/replacement/profile UX remains in later tasks. No release/publication.
