# VER-QA-002 — Authenticated Azure subscription inventory

```json verification-metadata
{
  "id": "VER-QA-002-AZURE-INVENTORY",
  "task_ids": ["QA-002"],
  "timestamp": "2026-11-13T05:22:00+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows PowerShell; workspace-local Azure CLI2.92.0; authenticated user-selected Azure for Students subscription; read-only Azure Resource Manager/catalog/policy/budget queries; public retail pricing. No resource creation or production backend access.",
  "commands": [
    "az login --tenant <observed-tenant> --output none (interactive browser/MFA)",
    "az account show --subscription <user-supplied-id> --query selected id/name/state/tenant fields",
    "az group list --subscription <id> --query selected name/location fields",
    "az resource list --subscription <id> --query selected name/type/group/location fields",
    "az rest GET /subscriptions/<id>?api-version=2022-12-01 --query state/subscriptionPolicies",
    "az rest GET /subscriptions/<id>/providers/Microsoft.Consumption/budgets?api-version=2024-08-01 --query selected budget fields",
    "az policy assignment list --scope /subscriptions/<id> --query displayName/parameters",
    "az vm list-skus --location southeastasia --resource-type virtualMachines --size Standard_B2s --all --query selected names/capabilities/restrictions",
    "az appservice list-locations --sku B1 --linux-workers-enabled --query [].name",
    "GET public Azure Retail Prices API for Linux Standard_B2s Consumption in southeastasia"
  ],
  "checks": [
    {"category": "azure-authentication", "outcome": "passed"},
    {"category": "azure-subscription-inventory", "outcome": "passed"},
    {"category": "deployment-config", "outcome": "unverified"},
    {"category": "live-backend", "outcome": "unverified"},
    {"category": "migration-rehearsal", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

Device-code sign-in was rejected with AADSTS530035 / security defaults; no security setting was disabled. A normal tenant-targeted browser login completed with exit0 and the subsequent account query succeeded. The exact user-supplied target resolves to **Azure for Students**, state **Enabled**, quotaId **AzureForStudents_2018-01-01**, spendingLimit **On**. Resource groups, resources and configured budgets each returned empty arrays. Actual remaining credit and expiry were not returned by these queries and are not inferred from an empty resource inventory.

The subscription's **Allowed resource deployment regions** policy allows `koreacentral`, `australiaeast`, `eastasia`, `centralindia`, `malaysiawest`. Southeast Asia is outside that list. Standard_B2s (2vCPU/4GB) and B2s_v2 (2vCPU/8GB) in Southeast Asia report `NotAvailableForSubscription` at location and zone levels. The generic Linux B1 App Service location catalog lists all five allowed regions, but this does not establish subscription-specific worker quota or deployability. No provider registration, quota adjustment or deployment was performed to test availability.

Public retail price for Linux Standard_B2s in Southeast Asia was USD0.0528/hour (effective2025-10-01), or USD38.544 at730 hours for compute only. This is a comparison, **not a deployable quote**: that region/SKU is restricted here, and disk/IP/backup/egress costs are additional. Check a permitted region and actual SKU/quota before a final cost proposal. USD100 is the user's total credit ceiling, not verified current balance or an indefinite hosting allowance. No cost alert or spending policy was changed.

## Evidence

Queries used the official workspace-local CLI against authenticated Azure control-plane endpoints; outputs were limited to nonsecret subscription/resource/policy fields. Account email, login codes, auth callbacks, tokens and private caches are excluded from shared evidence. The browser helper's ignored state file reports successful completion at2026-11-13T05:17:47+08:00. Public price lookup used the [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices). Concurrent [AZ-001](../progress/tasks/AZ-001.md) worker adapter work was not modified by this inventory.

## Limits and next action

No Azure live app/backend exists. Resolve the conflicting full-migration versus workers-only scope, select an allowed region/SKU with actual quota, verify remaining credit/expiry and hosting duration, then prepare the concrete deployment/cost plan. Full migration additionally requires secure source export, consistent database/media restore and client endpoint rollout. Do not weaken tenant security defaults, change to paid billing or use an unavailable region to bypass the student policy. USB is still unstable/offline; no device acceptance passed. QA-001/REL-001, M2, migration and release gates remain open.

### 2026-11-13T05:23:30+08:00 — Permitted-region B2 catalog follow-up

`az vm list-skus --location malaysiawest --resource-type virtualMachines --size Standard_B2 --all --query '[?length(restrictions)==0]...'` completed successfully with an empty array. This check found no unrestricted matching B2 VM in that permitted region; it does not establish that all VM sizes or other allowed regions are unavailable. Do not select B2 or quote a deployable full-backend server based on the earlier public Singapore rate. Further capacity/cost selection depends on the final hosting scope; nothing was provisioned.
