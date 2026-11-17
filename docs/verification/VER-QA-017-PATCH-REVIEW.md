# Review packet: two Azure migration security fixes

```json verification-metadata
{
  "id": "VER-QA-017-PATCH-REVIEW",
  "task_ids": [
    "QA-017"
  ],
  "timestamp": "2026-11-14T13:01:50.156+08:00",
  "tested_commit": "734d80093c1a340c87eab1b2b3b5303372e63319",
  "dirty_tree": true,
  "environment": "Read-only Azure Supabase migration destination catalog; source patch matches previously native-tested QA-00752-migration revision",
  "commands": [
    "Azure VM read-only catalog command with BEGIN READ ONLY",
    "SHA256 compare both migration files against QA-007-results.json"
  ],
  "checks": [
    {
      "category": "deployed-catalog",
      "outcome": "passed"
    },
    {
      "category": "migration-source",
      "outcome": "passed"
    },
    {
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

The selected Azure migration environment (rg-tabby-backend-eastasia/tabby-supabase) remains at50 migration rows/latest20261104000002. Client INSERT on friendships remains granted; neither pending security patch is applied. Probe used an explicit read-only DB transaction and returned catalog/aggregate metadata only. No schema/data change was made.

Apply only these exact source files after target-scoped approval:

- [20261113000001_friendship_rpc_only.sql](../../supabase/migrations/20261113000001_friendship_rpc_only.sql), SHA256 6e4013f751d85e1e62e99e7439498f8ea8d29b7e8e0f544528cd09f1bc640bf1
- [20261113000002_friend_request_pair_lock.sql](../../supabase/migrations/20261113000002_friend_request_pair_lock.sql), SHA256 a960f4cb56619d7a1ad307ceaaeba89f86bffc5c834f1a274bb55e8fe012776d

First patch removes the legacy friendship INSERT policy and client grant, preserving guarded recipient-consent RPCs; it also repairs declined resend and acceptance notification contracts. Second patch serializes requests for the same immutable pair to avoid opposing requests/unique conflicts. Existing friendship and financial rows are preserved; no data-repair/backfill is included.

The files match [native fresh/upgrade/privacy/concurrency52-migration evidence](VER-QA-007-SOCIAL-CONCURRENCY.md) byte for byte. That source evidence does not prove deployed Auth/Storage/Realtime acceptance.

## Evidence

[QA-007 source hashes](QA-007-results.json), [consent repair](VER-QA-006-FRIENDSHIP.md), [task](../progress/tasks/QA-017.md). Raw metadata log remains ignored locally; it contains no credentials or record bodies.

## Limits and next action

Before applying: create a new encrypted database backup on the migration VM, verify the protected recovery key/backup digest and retain recovery material privately; verify current50-row inventory and these digests again. Use one deployment lock and transaction for both additive source bodies plus migration-history rows, and abort on unexpected inventory or grant state. Compare existing confirmed-history fingerprints before/after, require authenticated friendship INSERT revoked, then notify PostgREST to reload. Verify live Auth denial and explicit request/recipient acceptance with tagged synthetic accounts only; preserve their audit trail and all original records. Original Supabase, client endpoint, signup/schedulers/M2 controls, resource/billing settings and public release remain unchanged.

A failure rolls back the transaction. After a committed patch, use forward repair; do not silently restore the insecure grant or rewrite applied history. No deployment result or release approval is claimed by this packet.

2026-11-14T14:20:41.074+08:00 — Superseding deployment evidence: user approved the exact reviewed packet; encrypted off-VM backup/recovery verification and atomic52-migration commit passed. Real tagged-Auth consent checks24/24 passed; see [deployed evidence](VER-QA-017-DEPLOYED.md). This does not authorize original-project changes or endpoint cutover.
