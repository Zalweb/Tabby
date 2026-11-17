# VER-AZ-001 — Local Azure worker deployment preparation

```json verification-metadata
{
  "id": "VER-AZ-001",
  "task_ids": ["AZ-001"],
  "checks": [
    {"category": "worker-adapter", "outcome": "passed"},
    {"category": "local-package", "outcome": "passed"},
    {"category": "deployment-config", "outcome": "unverified"},
    {"category": "azure-inventory", "outcome": "unverified"},
    {"category": "live-endpoint", "outcome": "unverified"},
    {"category": "integration-review", "outcome": "unverified"}
  ],
  "timestamp": "2026-11-13T05:13:06+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows PowerShell; Node 26.13.0 initially, then cached Node 24.22.1 matching the target major; synthetic credentials and mocked providers; loopback HTTP only. Public Azure retail pricing, GitHub repository metadata, locally installed Azure MCP Server 2.0.5. No cloud deployment.",
  "commands": [
    "node --test backend/app.test.mjs scripts/test-account-deletion-worker.mjs scripts/test-account-deletion-transport.mjs scripts/test-reminder-push-worker.mjs scripts/test-recurring-worker.mjs (Node 26.13.0 and Node 24.22.1)",
    "node scripts/azure-package.cjs",
    "node --test scripts/azure-package.test.mjs (Node 24.22.1)",
    "PowerShell Parser.ParseFile scripts/azure-appservice.ps1; ConvertFrom-Json deploy/azure/main.json and parameters.example.json",
    "YAML 2.9.1 parse .github/workflows/deploy-azure-workers.yml",
    "gh api repos/Zalweb/Tabby --jq selected default_branch/private/permissions fields",
    "GET Azure Retail Prices API filtered for Azure App Service, southeastasia, B1; select Linux Consumption rows",
    "Azure MCP Server 2.0.5 stdio initialize, tools/list and subscription_list read attempts",
    "Azure MCP CLI subscription list --retry-max-retries 0 --retry-network-timeout 10 (interactive sign-in pending)",
    "Azure MCP CLI get_azure_bestpractices get --resource general --action deployment",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0",
    "git diff --check"
  ]
}
```

## Expected and actual results

Worker/transport suite passed **28/28** on both Node 26.13.0 and Node **24.22.1**. Seven adapter tests verify default-disabled behavior, safe settings, service bearer plus independent route secret on every worker (including push), bounded recurrence dispatch, exact reviewed Auth/Storage transport, Firebase authorization/queue boundary and native HTTP body/log safeguards. Existing 21 tests cover retained worker semantics. Providers are mocked and all identities/secrets are synthetic.

Packaged-startup test passed **1/1** on Node 24.22.1: the staged package starts with its declared command and no credentials, health returns 200, readiness returns 503 and all three disabled worker POSTs return 503. This verifies the deployment file layout on Windows locally, not Azure Linux startup.

ARM/parameter JSON parsing and PowerShell AST parsing passed. Workflow YAML parsed with `yaml@2.9.1`; hosted GitHub Actions, Azure RBAC/OIDC, ARM service validation/what-if, cloud runtime, logs and authenticated provider behavior remain unverified. No third-party runtime dependencies were added. Local YAML/MCP tooling is installed only under ignored `.dart_tool/azure-tools`.

Public pricing returned Linux B1 Singapore USD 0.018/hour; 730 hours = USD 13.14 compute/month. GitHub metadata confirms `main` as default branch. No Azure account-specific prices/resources/credits are established. No cached Azure CLI subscription profile was found at this checkpoint.

## Evidence

- [Adapter and HTTP bridge](../../backend/app.mjs), [adapter tests](../../backend/app.test.mjs), [package smoke test](../../scripts/azure-package.test.mjs).
- [ARM template](../../deploy/azure/main.json), [CLI executor](../../scripts/azure-appservice.ps1), [workflow](../../.github/workflows/deploy-azure-workers.yml), [cost estimate](../../deploy/azure/cost-estimate.json), [runbook](../project/AZURE_DEPLOYMENT.md).
- Staged adapter SHA-256: `13d60424967efc19b6a001ce099966fe42822cec747137ca9e19c49539a61e1b`. No zip has been deployed; an approved deploy must record its exact package digest and source revision.
- Initial Node test subprocesses and Git subprocess coverage were denied by sandbox EPERM; approved retries passed. A planned packaged-startup run was interrupted by the user; its resumed Node 24 run passed. Python YAML import was unavailable; the subsequent dedicated Node YAML parser passed. PowerShell blocked `npm.ps1`; `npm.cmd` succeeded without changing execution policy.
- Azure MCP plugin discovery found no App Service connector. A pinned Microsoft Azure MCP Server 2.0.5 was subsequently installed locally. Read-only stdio initialization succeeded; tool discovery/subscription requests timed out after 45 seconds. A subscription-list CLI call using that server then initiated Microsoft's device sign-in flow. User sign-in is pending; no codes or credentials are retained in repository evidence. Best-practice retrieval succeeded.
- Concurrent QA-002 USB/platform/workflow/documentation changes were preserved. Their verification claims are separate from AZ-001.

## Limits and next action

Complete Azure sign-in, refresh read-only inventory through Azure MCP, determine subscription/offer/remaining credit/expiry/quota/region, evaluate existing plan reuse, validate the template and present exact target parameters/cost for approval. The latest historical live Supabase audit had migration/authorization failures; refresh that inventory and verify staging before enabling workers. Follow the [deployment runbook](../project/AZURE_DEPLOYMENT.md) after approval, then record actual endpoints, logs and migration/provider evidence. No Azure resources, Supabase mutations, GitHub publication/configuration, live processing or deployment has occurred. AZ-001 stays in progress.
