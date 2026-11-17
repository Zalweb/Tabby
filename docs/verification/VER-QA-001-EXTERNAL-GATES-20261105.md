# VER-QA-001-EXTERNAL-GATES-20261105 — environment availability and live schema recheck

```json verification-metadata
{
  "id": "VER-QA-001-EXTERNAL-GATES-20261105",
  "task_ids": ["QA-001", "REL-001"],
  "timestamp": "2026-11-05T22:28:13+08:00",
  "tested_commit": "241bdfd588fe0547ccde36a516c6eab5e59ba8b6",
  "dirty_tree": false,
  "environment": "Windows PowerShell; read-only Supabase Management API query against the production Tabby project; local adb inventory; no user financial rows fetched",
  "checks": [
    {"category": "live-backend", "outcome": "failed"},
    {"category": "backend-authorization", "outcome": "failed"},
    {"category": "backend-integration", "outcome": "failed"},
    {"category": "android-device", "outcome": "unverified"},
    {"category": "integration-review", "outcome": "unverified"},
    {"category": "release-artifact", "outcome": "unverified"},
    {"category": "upgrade", "outcome": "unverified"}
  ],
  "commands": [
    "POST /v1/projects/ziaqrkagsvozhotremsx/database/query/read-only with SELECT-only metadata query",
    "adb devices -l"
  ]
}
```

## Expected and actual results

The Management API reported `transaction_read_only=on` as `supabase_read_only_user`, with 18 migration-history rows ending at `20261030000004`. The live project still has `public.get_pair_outstanding(uuid,uuid,uuid)`, and `authenticated` still has EXECUTE on that function. `public.create_expense_v1(uuid,jsonb)` and `public.expense_review_state_v1(uuid)` are absent. These findings confirm the deployed project is behind the repository contract and its authorization gate remains failed/open. This query read catalog/history metadata only and fetched no user rows.

`adb devices -l` listed no devices. Previous read-only staging discovery recorded only the production project and no disposable hosted project; local Supabase startup was blocked because Docker and Podman were unavailable. No authenticated end-user JWTs or two fixture accounts are available for live API journeys. No authenticated request, write, migration, deployment, or configuration change was attempted.

## Evidence

This recheck is bounded to live migration count/version and exact RPC/grant metadata. The earlier detailed catalog inventory and anonymous probes are in [VER-QA-001-LIVE-READONLY](VER-QA-001-LIVE-READONLY.md); staging provisioning blockers are in [VER-M2-SUPABASE-AUTH-STAGING](VER-M2-SUPABASE-AUTH-STAGING.md). Local PostgreSQL/PostgREST results remain separate and do not satisfy this live gate.

## Limits and next action

`backend-integration`, `backend-authorization`, and `live-backend` remain failed/open pending an authorized non-production Supabase project with the current migrations deployed and Auth-issued fixture accounts. Do not apply repository migrations or test writes to production. `android-device` remains unverified until a physical supported device is attached and the required matrix is run. `integration-review` remains unverified until an independent reviewer reviews the integrated source and evidence. `release-artifact` and `upgrade` remain unverified until an authorized protected release run produces an exact signed candidate and the candidate is upgraded on a supported device. No M2 flag or release gate was enabled.
