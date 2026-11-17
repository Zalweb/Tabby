# VER-QA-002 — Azure full-backend destination execution

Superseding2026-11-13: the following is provisioning history. Source database/media restore,32-migration upgrade, off-VM key/backup recovery and26 real Auth/finance/Storage/worker-denial checks are now verified in [current restore/live evidence](VER-QA-002-AZURE-RESTORE.md). Own-address SMTP delivery is confirmed. Original production/client endpoint remains unchanged; full cutover and release gates stay open.

```json verification-metadata
{
  "id": "VER-QA-002-AZURE-FULL",
  "task_ids": ["QA-002"],
  "timestamp": "2026-11-13T06:08:00+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows PowerShell/Node26.13/Azure CLI2.92.0; authenticated Azure for Students; real East Asia B2als_v2 VM,4GB/64GB SSD; official self-hosted Supabase v0.8.4 with explicit PG17.11 and PostgREST16.5 overrides; public HTTPS and real source read-only management/Storage export. Production source remains unchanged.",
  "commands": [
    "az vm list-skus --all --resource-type virtualMachines (locally filtered against allowed regions/capabilities/restrictions)",
    "az provider register Microsoft.Compute/Microsoft.Network/Microsoft.Storage",
    "az vm list-usage --location eastasia",
    "GET public Azure Retail Prices API for actual East Asia VM/disk/IP meters",
    "az group create rg-tabby-backend-eastasia --location eastasia",
    "node scripts/azure-full-template.cjs <public-local-config> <ignored-ARM-output>",
    "az deployment group validate; az deployment group create tabby-full-20261113; az deployment group show",
    "az rest PUT/GET Microsoft.Consumption/budgets/tabby-credit-guard (owner contact excluded from shared evidence)",
    "az vm run-command invoke for sanitized status, platform prerequisites/Auth ownership repair and runtime alignment",
    "node scripts/azure-full-probe.cjs <destination-HTTPS-origin> <ignored-client-config>",
    "node --test scripts/azure-full-template.test.cjs scripts/azure-full-seal.test.cjs",
    "bash -n deploy/azure-full/bootstrap.sh; bash -n deploy/azure-full/initialize-platform.sh; Python ast.parse generate-env.py",
    "scripts/azure-full-export-assets.ps1 (source read-only, encrypted output only)",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0"
  ],
  "checks": [
    {"category": "azure-infrastructure", "outcome": "passed"},
    {"category": "deployment-config", "outcome": "passed"},
    {"category": "azure-platform-health", "outcome": "passed"},
    {"category": "platform-denial-probes", "outcome": "passed"},
    {"category": "automation-regression", "outcome": "passed"},
    {"category": "encrypted-asset-export", "outcome": "passed"},
    {"category": "fresh-bootstrap", "outcome": "unverified"},
    {"category": "migration-rehearsal", "outcome": "unverified"},
    {"category": "live-backend", "outcome": "unverified"},
    {"category": "usb-device", "outcome": "unverified"},
    {"category": "integration-review", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

User directed execution after previously selecting full migration; [DEC-012](../project/DECISIONS.md#dec-012--stage-the-full-supabase-backend-on-azure-before-cutover) records the active scope. Global SKU inspection found unrestricted Standard_B2als_v2 in permitted East Asia. After registering the previously unregistered providers, quota was6 regional cores with10 Basv2-family cores, current usage0. ARM validation succeeded; actual deployment `tabby-full-20261113` succeeded and VM is running. The subscription spending limit stayed On. A real USD90 annual budget was created and its currency verified USD; alert recipients are excluded here. No paid-billing conversion occurred.

The initial prepared database image skipped expected platform setup: Auth first failed database authentication, then missing platform-role setup and ownership of `auth.uid()`. Repairs applied upstream initialization and correct Auth ownership without deleting/reinitializing the database. PostgREST next reported missing `graphql_public`; the namespace was initialized. All12 container health checks then passed. The original cloud-init error remains recorded. The runtime was subsequently aligned to PostgreSQL17.11 (official image17.11.0.019) and PostgREST16.5; all containers again passed health. Repaired source automation is present, but a completely fresh run of the revised bootstrap has not been exercised.

The public HTTPS probe passed6/6: Auth health200 with client key; Auth settings200 with signup disabled; no-key request401; client request to a nonexistent table404/PGRST205, confirming it reaches PostgREST; OpenAPI root403 under upstream gateway RBAC; dashboard401 without Basic Auth. These are platform and denial probes only: no financial schema, migrated accounts or user journey is established. Live origin is `https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com`.

Two template security regressions and two encryption tests passed. Shell/Python syntax checks passed. Source management queries confirmed PostgreSQL17.11,18 applied migrations through20261030000004 and about14MB, with sanitized counts7 Auth users/3 expenses/0 payments/3 Storage objects. Source private media/provider configuration was exported into encrypted ignored storage (3 objects), with SHA256/ownership metadata. The first asset export hit a PowerShell array-wrapper issue; it was corrected, and UTF8 input encoding was made explicit before the successful snapshot. Crypto tests verify round-trip, randomized encryption and tamper rejection. No plaintext media/provider export or source service key was written to Git or logs.

## Evidence

Deployment sources and operations are in [azure-full](../../deploy/azure-full/README.md). Real public probes: [script](../../scripts/azure-full-probe.cjs); ignored `.dart_tool/azure-full/platform-probes.json`. Sanitized provisioning/status/repair/version outputs remain ignored under `.dart_tool/azure-full/`; original ARM output `main.json` identifies the initial provisioning artifact, while later runtime/initialization repairs are recorded separately. The latest encrypted asset snapshot is `.dart_tool/azure-full/source-assets-20261113.sealed.json`; it is not a database backup. No auth codes, passwords, account emails, private media bytes or source financial rows appear in shared evidence. Two legacy non-UTF8 byte sequences in the decisions document were normalized losslessly so the dated hosting decision could be appended; existing claims were preserved.

## Limits and next action

The source database credential is not yet supplied; original users, financial rows, migration history and media are not restored on Azure. Do not call the empty platform a completed Tabby backend migration. Next obtain ignored SUPABASE_DB_URL, perform consistent database export/restore with version reconciliation, restore/check media and provider configuration, deploy actual worker functions/secrets/schedulers and run real Auth/Storage/financial positive/negative journeys. Keep original production and Flutter URL unchanged until validation and cutover. Required physical USB, fresh-bootstrap, independent review and QA-001/REL-001 gates remain open. The destination incurs ongoing charges (base estimateUSD46.85/month plus operations/egress/backup), under the existing student credit limit; alerts are not a hard stop. No App Service workers-only hosting was deployed.
