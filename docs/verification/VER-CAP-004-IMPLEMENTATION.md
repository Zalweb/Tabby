# VER-CAP-004-IMPLEMENTATION

```json verification-metadata
{
  "id": "VER-CAP-004-IMPLEMENTATION",
  "task_ids": [
    "CAP-004"
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
      "category": "backend-contract-local",
      "outcome": "passed"
    },
    {
      "category": "concurrency-local",
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
  "timestamp": "2026-11-02T00:39:40.215Z",
  "tested_commit": "b8cd84355e0c3b20958753ef730bce7bf0009a69",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8. Source and local fixtures only; no attached Android device or live backend.",
  "commands": [
    "flutter analyze --no-pub lib test scripts",
    "flutter test --no-pub",
    "node scripts/test-backend-native.cjs",
    "node --test scripts/check-project-memory.test.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base b8cd84355e0c3b20958753ef730bce7bf0009a69",
    "git diff --check"
  ]
}
```

## Expected and actual results

Flutter analyze: no issues. Full suite: 644/644 passed, including exact selection/consent, frozen reopen retry, explicit decline, account expiry and owner decision denial. Native PostgreSQL 17.11 source suite and eight-session acceptance race passed: one offset/one transfer; original contact participant references and expense bytes retained; decline leaves identity/financial rows unchanged; stale history and foreign decisions denied; both debt directions and existing registered-tab balance accumulation tested. Initial SQL field/variable/fixture assumptions and Flutter guard API/lints were corrected; final checks passed. Local fixtures do not establish live backend/device acceptance.

## Evidence

Implemented hidden exact friend-code selection, owner invitation, recipient inbox, paged retained expense/payment history and explicit acceptance/decline screens using the shared durable queue. Server freezes source digest/net, rejects stale or ambiguous sources and pending financial decisions, and serializes legacy financial DML before acceptance. Decline changes only the invitation. Acceptance retains originals/contact references, appends an offset and registered-tab transfer, records output references, links consent and closes the source ledger. Legacy identity-rewriting claim RPC access and direct claim-field bypasses are blocked. Both client and server rollout flags remain disabled.

Regression sources: test/features/contact_claim_test.dart and scripts/test-contact-claims.cjs, plus native independent-session fixture. Table locks are deliberately short and limited to explicit claim decisions; staging contention/retry behavior is still unverified.

## Limits and next action

Real device/offline/account switching, authenticated live Supabase/PostgREST inventory, fresh/upgrade deployment, independent integration review and M1 dependencies remain unverified. Ambiguous multi-tab contact histories, pending financial decisions, over 5000 expenses or net balance above the normal command limit require explicit reconciliation before invitation. No automatic name/phone matching or financial identity rewrite. No release gate closed. Next: Independent review and real staging/device tests before rollout; continue CAP-005.
