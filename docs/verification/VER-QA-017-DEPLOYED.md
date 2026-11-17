# QA-017 — Approved Azure friendship security patch and live consent acceptance

```json verification-metadata
{
  "id": "VER-QA-017-DEPLOYED",
  "task_ids": [
    "QA-017"
  ],
  "timestamp": "2026-11-14T14:20:41.074+08:00",
  "tested_commit": "734d80093c1a340c87eab1b2b3b5303372e63319",
  "dirty_tree": true,
  "environment": "Approved Azure migration VM tabby-supabase in rg-tabby-backend-eastasia; self-hosted Supabase HTTPS; tagged synthetic Auth accounts",
  "commands": [
    "python3 apply.py --packet <sealed scoped packet> --mode prepare",
    "operator off-VM encrypted backup download/decrypt/hash verification in memory",
    "python3 apply.py --packet <same sealed packet> --mode commit --verified-backup-sha256 <verified ciphertext digest>",
    "TABBY_PATCH_FOLDER=<scoped private run> python3 verify-consent.py",
    "python deploy/azure-full/test_readiness_patch.py"
  ],
  "checks": [
    {
      "category": "migration-source",
      "outcome": "passed"
    },
    {
      "category": "deployed-catalog",
      "outcome": "passed"
    },
    {
      "category": "backend-integration",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

User explicitly approved the reviewed two-migration patch. Created an encrypted pg_dump backup, verified pg_restore listing and private off-VM Blob readback, recovered/decrypted with the operator key in RAM and verified its digest without persisting plaintext. Rehearsed both exact SQL bodies/journal rows then rolled back; committed identical sealed packet atomically under advisory lock. Destination now has52 migrations including20261113000001/00002; authenticated direct friendship INSERT is revoked. Four existing financial-table fingerprints remained unchanged. Real HTTP/Auth consent acceptance passed24 checks: direct accepted INSERT denied, stranger hidden, opposing sends produce one pending plus inbound notice, stable replay, requester/outsider rejection, recipient-only acceptance/canonical pair and visibility. Three fresh fixtures in final run were signed out/banned and re-login rejected.

Run readiness-20261114T052749Z-de835256; final live attempt20261114T054937Z-eac215 passed24/24 and fixture retirement. Two bootstrap env/origin harness failures preceded fixture creation. A first live attempt used an incorrect expectation of two successful opposing replies; product contract was re-read, expectation corrected to one200 and one400/P0001, SQL unchanged. Both that attempt’s three fixtures and final three fixtures were retired. Python guard tests4/4 pass. Sanitized backup/commit/live results linked below; financial row bodies and secrets excluded.

## Evidence

[Sanitized current results, artifacts, source delta and log digests](QA-018-results.json). Tested source is base 734d80093c1a340c87eab1b2b3b5303372e63319 plus the recorded dirty-tree delta. APPLIED on the explicitly approved Azure migration destination only. Existing private storage reused, no new paid resource/billing change. Original Supabase, installed production app, client defaults and existing confirmed history untouched.

## Limits and next action

Original Supabase was not changed or assessed by this deployment. No default endpoint cutover or financial repair. Full backup restore to a clean full stack, provider/Storage/migration cutover acceptance and independent integration review remain open. Do not rerun this50→52-only operator against the now52 catalog.

Review the deployed evidence; keep full provider/cutover and recovery-restore gates open. No duplicate patch application.
