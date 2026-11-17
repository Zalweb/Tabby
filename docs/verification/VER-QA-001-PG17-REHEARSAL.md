# VER-QA-001-PG17-REHEARSAL — local PostgreSQL 17 migration rehearsals

```json verification-metadata
{
  "id": "VER-QA-001-PG17-REHEARSAL",
  "task_ids": ["QA-001", "LED-003", "PAY-001", "PAY-004", "SEC-002"],
  "tested_commit": "b26767489a1b32a91853dfbce5180eb4834909e7",
  "dirty_tree": true,
  "timestamp": "2026-11-04T01:41:37+08:00",
  "agent": "Codex root",
  "platform": "Windows",
  "environment": "Embedded native PostgreSQL 17.11; local disposable databases; no live project access",
  "checks": [
    {"category": "fresh_install", "outcome": "passed"},
    {"category": "source_equivalent_upgrade", "outcome": "passed"},
    {"category": "exact_live_baseline_upgrade", "outcome": "failed"},
    {"category": "pair_helper_local_authorization", "outcome": "passed"},
    {"category": "production_upgrade_readiness", "outcome": "unverified"},
    {"category": "integration", "outcome": "unverified"},
    {"category": "backend-integration", "outcome": "failed"},
    {"category": "backend-authorization", "outcome": "failed"},
    {"category": "android-device", "outcome": "unverified"},
    {"category": "regression", "outcome": "unverified"}
  ],
  "commands": [
    "node .dart_tool/native-db/qa-migration-rehearsal.mjs",
    "node scripts/test-m2-schema-snapshot.cjs"
  ]
}
```

## Expected and actual results

Expected: all 48 ordered migrations apply on fresh PostgreSQL 17; the ordered missing migration set applies to a faithfully reconstructed 18-row live baseline; fresh and upgraded schema contracts match; the helper revoke blocks authenticated direct invocation while preserving owner access. Actual: fresh 48/48 passed (918 statements); 32/32 source-equivalent pending migrations passed (462 statements) and matched fresh schema inventory; exact live baseline fidelity failed (two functions and one public policy were not reproduced); local helper revoke passed. Production-upgrade readiness is therefore unverified.

## Evidence

The per-file statement counts, per-file driver result counts, complete fresh/baseline/upgrade inventories (tables, columns, indexes, triggers, functions, policies, realtime members and histories), contract probes, ACL results, and ordered migration versions are in [VER-QA-001-PG17-INVENTORY.json](VER-QA-001-PG17-INVENTORY.json). The inventory is sanitized and excludes temporary cluster paths. PostgreSQL was embedded native 17.11 on Windows; the M2 schema snapshot check passed 1/1.

## Scope and safety

This rehearsal used a throwaway embedded PostgreSQL 17.11 cluster on loopback and local databases only. Supabase `auth`, `storage`, roles, and the realtime publication were represented by local harness prerequisites. Nothing in this run connected to, queried, or mutated the live Supabase project. No deployment, DDL, grant, DML, cache reload, or Supabase configuration action was performed remotely. The temporary runner and raw machine report remain under ignored `.dart_tool/native-db/`; the sanitized durable inventories are in [VER-QA-001-PG17-INVENTORY.json](VER-QA-001-PG17-INVENTORY.json).

The native PostgreSQL parser rejected UTF-8 BOM bytes preceding `BEGIN` in `20261102000011_explicit_contact_claims.sql` and `20261102000012_expense_review.sql`. Those two leading encoding markers were removed; SQL statement contents were unchanged. The final successful run below used the resulting source. This explains `dirty_tree: true` for the tested source snapshot.

## Fresh install — passed

Applied all 48 version-ordered migration files. The SQL statement lexer counted 918 statements, and the PostgreSQL driver completed all 918 without an error (the per-file statement and driver counts are in the JSON inventory). The run ended with 46 public tables, 340 columns, 125 indexes, 65 noninternal public triggers, 133 public functions, 99 public and 10 storage policies, two `supabase_realtime` members (`notifications`, `transaction_participants`), and 48 migration-history rows.

The contract probes found the plan-dependent M2 tables and RPC signatures, and confirmed that `payments.amount_centavos`, `transactions.total_amount_centavos`, `transaction_participants.share_amount_centavos`, `recurring_rules.amount_centavos`, and `expense_change_requests.new_total_centavos` are `bigint`/`int8`. All four rollout flags (`contact_claiming`, `custom_splits`, `expense_review`, `recurring`) were false. `node scripts/test-m2-schema-snapshot.cjs` passed 1/1, confirming the disabled M2 migration snapshot remains byte-synchronized after removing the two BOM markers. This verifies local schema creation only; it does not enable M2 or prove Supabase HTTP behavior.

## Upgrade rehearsal — source-equivalent pass; exact-live-baseline gate failed

The runner applied 18 source-equivalent baseline files (472 statements) to construct the measured old-era shape. It then replaced only the local `schema_migrations` rows with the exact 18 captured live version/name pairs (their `statements[]` contents were unavailable and stored empty), before applying the 32 files absent by local version ID (462 statements). All 32 files completed without SQL errors or missing-object failures. The resulting schema inventory matched the fresh-install inventory exactly for tables, columns, indexes, triggers, functions, policies, realtime members, helper ACL, payment caller metadata, and contract probes: 46 tables, 340 columns, 125 indexes, 65 triggers, 133 functions, 109 policies across public and storage, and two realtime members. Migration history intentionally differs: 50 rows in the upgrade DB versus 48 on fresh install. The JSON records the source-built baseline inventory before the local history-row replacement and separately records the exact captured live history rows.

This is a clean local migration execution chain against that reconstruction. It is **not** an exact reproduction of production’s measured baseline: production was measured at 18 public tables, 17 old-era triggers, 42 functions, 60 public policies, and 18 history rows. The source-derived baseline has 18 tables, 17 triggers, 40 functions, 59 public policies (plus 8 storage policies), and 18 history rows. The live `schema_migrations` read did not include original `statements[]`, so the two missing functions and one missing public policy could not be reconstructed exactly. Exact-live-baseline upgrade therefore failed its precondition and production upgrade readiness remains unverified.

History also remains mismatched after rehearsal: 50 rows rather than the fresh install’s 48, because the two locally replayed September migrations are already represented in live history under different version IDs. The remote rows are `20260930161339` / `20260930000001_friendship_realtime_notifications` and `20260930161351` / `20260930000002_tab_reminders_realtime`; repository IDs are `20260930000001` and `20260930000002`. Do not simply run/reconcile these two versions in production without reviewing their original recorded statements and resolving migration-history provenance.

## Pending versions in repository order

The ordered local versions absent by exact version ID in the captured live history are:

1. `20260930000001` — live history has a likely content-equivalent migration under version `20260930161339`; version mismatch, original remote statements unavailable.
2. `20260930000002` — live history has a likely content-equivalent migration under version `20260930161351`; version mismatch, original remote statements unavailable.
3. `20261001000001`
4. `20261001000002`
5. `20261031000001`
6. `20261031000002`
7. `20261031000003`
8. `20261031000004`
9. `20261031000005`
10. `20261031000006`
11. `20261101000001`
12. `20261101000002`
13. `20261101000003`
14. `20261101000004`
15. `20261101000005`
16. `20261101000006`
17. `20261101000007`
18. `20261101000008`
19. `20261101000009`
20. `20261101000010`
21. `20261102000001`
22. `20261102000002`
23. `20261102000003`
24. `20261102000004`
25. `20261102000005`
26. `20261102000006`
27. `20261102000007`
28. `20261102000008`
29. `20261102000009`
30. `20261102000010`
31. `20261102000011`
32. `20261102000012`

Items 3–32 (30 versions) were absent from the captured live history. This is the ordered source list for planning only, **not** authorization to apply migrations.

## Data impact and blockers

- `20261101000004_atomic_payment_methods.sql` performs a one-time rewrite/backfill of existing `payment_methods.is_default` preferences, then inserts a `payment_method_revisions` snapshot for every existing method. The throwaway database had no real payment-method rows, so the data-dependent impact was not exercised. Before any production decision, perform a separately approved read-only count/impact review and test the migration against representative data in disposable staging.
- `20261101000009_profile_avatars.sql` upserts private bucket metadata; `20261102000009_custom_splits.sql` seeds four M2 flags false. These statements were exercised only against local harness tables.
- `20261001000001_add_users_payment_columns.sql` contains a local `NOTIFY pgrst, 'reload schema'` statement. No live notification or schema-cache reload was sent.
- Other DML statements found by source inspection are inside function bodies and were not invoked by applying the migrations. The migration that drops classroom tables, `20261030000003`, is already represented in the captured live history and is not on the exact-version pending list.
- The exact live baseline is not reproduced; two history IDs are drifted; data-backfill impact is untested against real rows; and live authenticated-user journeys/device acceptance remain open. These block any production-upgrade conclusion.

## Authorization reconciliation — local result passed; live gate open

`20261031000001_restrict_pair_outstanding.sql` contains:

```sql
REVOKE ALL ON FUNCTION public.get_pair_outstanding(UUID, UUID, UUID)
    FROM PUBLIC, anon, authenticated;
```

The helper remains `SECURITY DEFINER` and its body does not add an `auth.uid()` or membership guard. The intended remediation is to revoke direct client execution while retaining owner execution for internal definer callers. In the source-derived baseline, `authenticated` direct invocation succeeded and catalog ACL showed authenticated `EXECUTE`; after applying this migration in the local upgrade rehearsal, direct invocation returned SQLSTATE `42501` (`permission denied for function get_pair_outstanding`), authenticated `EXECUTE` was false, and owner `EXECUTE` remained true. Internal function callers and subsequent payment-decision definitions were inventoried locally. This verifies the local ACL behavior, not deployed authorization or full legitimate-user HTTP journeys.

The exact production corrective migration version is **`20261031000001`**. It was not applied to the live project. Backend authorization remains failed/open until a separately authorized deployment and authenticated outsider/member end-to-end checks occur.

## Verification outcome and next action

Fresh install passed; source-equivalent local upgrade passed without SQL failure; exact-live-baseline upgrade failed the baseline-reproduction precondition; local helper revoke behavior passed. No migration failure or missing-object dependency occurred in either successful local apply. Production upgrade readiness is unverified, not passed. Resolve migration-history provenance, reproduce the exact live functions/policies and original history statements, audit the payment-method backfill on representative staging data, then re-run upgrade rehearsal from that exact baseline. Keep M2 flags false and do not deploy as part of this evidence work.

## Limits and next action

The local baseline is source-derived, not a copy of production. Its missing two functions/one public policy and absent remote `statements[]` prevent an exact upgrade conclusion; two September remote migration IDs also drift. The payment-method preference/revision backfill was run against an empty fixture and needs impact review on representative disposable data. Next: reconcile migration provenance, construct a faithful staging baseline, inspect the backfill impact, and repeat upgrade/authorized HTTP checks there. No production write is part of the next local verification step.
