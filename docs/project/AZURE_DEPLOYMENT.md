# Azure App Service worker deployment

> Coordination update — 2026-11-13T05:52:00+08:00: [DEC-012](DECISIONS.md#dec-012--stage-the-full-supabase-backend-on-azure-before-cutover) records the active session's full-migration execution. QA-002 has provisioned `rg-tabby-backend-eastasia` and a self-hosted destination; source import/cutover remains pending. The workers-only proposal below is preserved, has not been deployed, and must not create a second paid hosting plan without a subsequent user direction. Earlier statements below about no resources/sign-in are historical for AZ-001, not current subscription inventory.

Owner: [AZ-001](../progress/tasks/AZ-001.md). User selection on 2026-11-13: **keep Supabase and host the three backend workers on App Service**. This supersedes the full-backend migration proposal in the concurrent [QA-002 runbook](AZURE_MIGRATION.md) for this deployment. Do not create that VM or migrate Auth/database/media as part of AZ-001. No Azure resources, deployment, secret updates, identity changes or GitHub configuration changes have been performed.

## Backend and production readiness

The app is Flutter/Dart with Riverpod/GoRouter and `supabase_flutter` (declared `^2.8.0`, resolved versions in `pubspec.lock`). The backend is Supabase PostgreSQL (local configuration: 17), SQL migrations/RPC/RLS, Auth, PostgREST, Storage and Realtime. Three Deno entry points use shared `.mjs` worker modules and built-in fetch/Web Crypto; there are no third-party worker runtime packages. Push uses Firebase HTTP v1 and a Google OAuth service account. The new [Node adapter](../../backend/app.mjs) reuses those worker modules with native Node HTTP, fetch and Web Crypto. No Express, database copy, npm install or container registry is required.

**Production is not ready.** Source inspection currently finds 50 migration files; deployment is not established by their presence. The [2026-11-05 live audit](../verification/VER-QA-001-EXTERNAL-GATES-20261105.md) observed only 18 migration history rows, missing RPCs and an unchecked helper grant. That is historical evidence, not a fresh live inventory. Refresh schema/history/grants read-only, reconcile drift, and verify current migrations in isolated staging before any production upgrade. AZ-001 does not apply SQL or silently change existing product contracts. Auth-issued multi-account authorization, Storage cleanup, provider delivery, recurrence flags, upgrade and independent integration review remain required. Local worker mocks cannot close those gates.

## Proposed hosting and cost

One Linux App Service **B1**, one instance (1 vCPU, 1.75 GB), Southeast Asia/Singapore; Node 24 LTS with platform patch updates; Always On; HTTPS only; TLS 1.2 minimum; FTP/basic publishing disabled; system-assigned managed identity. Key Vault Standard holds five server secrets; the app has only the vault-scoped Secrets User role. No ACR, VM, Azure SQL/PostgreSQL, private endpoint, paid Log Analytics workspace or extra replica is provisioned. App Service filesystem logs are used initially; configure retention/monitoring appropriate to actual operations after approval.

The public Azure Retail Prices API returned `Azure App Service Basic Plan - Linux`, B1, `southeastasia`, USD **0.018 / 1 Hour** on 2026-11-13. At 730 hours: **USD 13.14/month**, **USD 157.68/year** compute. At a full USD 100 credit balance, compute alone covers approximately **7.6 months**, before other services or credit expiry. The QA-002 record mentions a total USD 100 student-credit ceiling; remaining credit/expiry and whether it applies to this scope must be confirmed from the subscription. Do not convert student billing or treat credits as free unlimited hosting.

Key Vault secret operations, outbound bandwidth, taxes, existing Supabase/Firebase costs and other subscription usage are additional and workload-dependent. **USD 15/month is a planning allowance for low traffic, not a cap or an all-in quote.** Need actual subscription pricing/quota, remaining credit, region availability and usage before approval to provision. Reuse an existing compatible plan with spare capacity if inventory supports it; the supplied new-plan template must be adjusted and re-reviewed for that case. F1 is for experimentation; Microsoft does not support production use on it. A B1 plan continues billing even when its web app is stopped. Budget alerts do not stop spending; Basic lacks deployment slots and autoscaling, so deploys can briefly restart the app.

Sources: [App Service Linux pricing](https://azure.microsoft.com/en-us/pricing/details/app-service/linux/), [Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices), [Node runtime/PORT](https://learn.microsoft.com/en-us/azure/app-service/configure-language-nodejs), [Key Vault references](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references).

## Access, review and approval

Initially no Azure MCP connector or Azure CLI/azd installation was available. Superseding checkpoint 2026-11-13T05:13:06+08:00: pinned Microsoft Azure MCP Server 2.0.5 was installed under ignored `.dart_tool/azure-tools`. Read-only stdio initialization succeeded; discovery/subscription calls timed out. The server's native subscription-list CLI initiated Microsoft device sign-in, pending user completion. No cached Azure CLI subscription profile was found; QA-002 is independently preparing portable CLI tooling, which was not yet usable at this checkpoint. No subscriptions, resources, quotas or account-specific prices have been inspected. Finish authentication to [Azure MCP Server](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/get-started), then list subscriptions/resource groups/plans/web apps/vaults and selected-region quotas read-only. Authenticate through normal Azure sign-in, never by sending tokens/passwords in chat. Native MCP CLI and stdio evidence must be distinguished; an `az` fallback is not MCP evidence.

After installing Azure CLI and signing in, these prepared commands inspect without creating resources:

```powershell
./scripts/azure-appservice.ps1 -Mode Inspect -SubscriptionId <subscription-id>
```

Use `deploy/azure/parameters.example.json` to prepare a credential-free parameter file with actual globally unique app/vault names, approved region, existing Supabase HTTPS origin and Firebase project ID. No environment credentials belong in this file. Obtain current subscription offer, remaining credit/expiry, available B1 capacity, selected names and resource group. Run Azure template validation/what-if against an existing group:

```powershell
./scripts/azure-appservice.ps1 -Mode Plan -SubscriptionId <id> -ResourceGroup <group> -ParametersFile <file>
```

Plan does not create a group. If the target group is new, present the local template and cost/name proposal first; after approval create the group, run Plan, then provision only the reviewed changes. Read-only template validation and what-if still require appropriate Azure permissions. Stop if unexpected existing-resource changes appear. The template creates a new B1 plan; do not reuse an occupied name without reviewing what-if. Template syntax has only been checked locally; ARM service validation remains unverified.

Present exact subscription/group/names/region/SKU, current price and remaining release gates for user approval. **Do not run Provision or Deploy, publish the workflow, enable automatic deployments, assign identity roles or change secrets before that approval.** The user explicitly requested this cost/deployment gate; it is not an additional permission requirement inferred from repository instructions.

## Approved provisioning and secrets

After approval only:

```powershell
./scripts/azure-appservice.ps1 -Mode Provision -SubscriptionId <id> -ResourceGroup <group> -ParametersFile <file> -Approved
```

The executor needs deployment rights plus permission to assign the vault role. `WORKERS_ENABLED=false` is deliberate. Add secrets directly in Azure Key Vault through its authenticated portal or an approved secure local credential mechanism. An operator needs the appropriate vault-scoped secret-write role; the app and GitHub deploy identity do not receive that role. Do not put values in CLI arguments, shell history, workflow YAML, GitHub variables, source control, logs or shared evidence:

| Vault secret | Runtime setting |
|---|---|
| supabase-service-role-key | SUPABASE_SERVICE_ROLE_KEY |
| privacy-review-secret | PRIVACY_REVIEW_SECRET |
| push-worker-secret | PUSH_WORKER_SECRET |
| recurrence-worker-secret | RECURRENCE_WORKER_SECRET |
| firebase-service-account-json | FIREBASE_SERVICE_ACCOUNT_JSON |

Each worker secret must be independent and at least 32 random bytes; the service key is Supabase's actual server-only service-role credential, never a client/publishable key. Firebase credentials need messaging permission in the selected project. The adapter validates resolved settings when enabled; unresolved Key Vault references prevent startup. Check Key Vault reference resolution and managed-identity RBAC propagation without printing secret values.

## Initial deployment and verification

```powershell
./scripts/azure-appservice.ps1 -Mode Deploy -SubscriptionId <id> -ResourceGroup <group> -AppName <app> -Approved
node scripts/azure-verify.mjs https://<actual-default-hostname> --expect-disabled
az webapp log tail --subscription <id> --resource-group <group> --name <app>
```

The [packager](../../scripts/azure-package.cjs) stages only the server, adapter, three shared worker modules and a package manifest under ignored `.dart_tool/azure-workers/package`; no `.env`, SQL, client files or credentials. Record package SHA-256 and deployed source revision. Discover `defaultHostName` from Azure, because new app hostnames can have generated suffixes. Check logs locally, redact provider/platform output before sharing and retain sanitized startup/request evidence. Adapter logs contain only event, allowlisted route, status and duration; no headers, query strings, account IDs, request/response bodies or exceptions.

`GET /healthz` is process liveness (200). `GET /readyz` is **configuration readiness only** (503 while disabled, 200 when configured); it does not prove a deployed RPC/provider works. Disabled worker routes return 503. Enabled worker POSTs without valid service authorization and the route-specific secret return 403. GET worker routes return 405. Requests over 2048 bytes are rejected before dispatch; account-deletion JSON retains its existing 1024-character validation. These probes never process a live request or queue.

Only after live prerequisites and approval to activate pass, set `WORKERS_ENABLED=true` in Azure using an approved settings-only update. Do not reapply the ARM template casually: it intentionally resets this flag to false. Re-run probes without `--expect-disabled` and inspect logs. Use dedicated staging fixture identities for authenticated behavior; never test deletion on a real account. A long deletion cleanup may exceed the App Service frontend request timeout; it remains resumable, and an HTTP timeout must not be treated as completion. Exercise this and retry/overlap in staging before enabling privacy processing.

Worker POST routes retain `/functions/v1/account-deletion`, `/functions/v1/reminder-push` and `/functions/v1/recurring-obligations`. All require the service bearer plus respectively `x-privacy-review-secret`, `x-push-worker-secret` or `x-recurrence-secret`. The adapter supplies the service boundary formerly provided by the Supabase gateway, including push. No public/client worker calls are introduced. No scheduler is created; inventory existing invokers and move push/recurrence invocations explicitly after staging, preserving secrets, leases and M2 flags. Keep old invokers paused during switchover. Account deletion remains operator-reviewed and must never be cron-driven. Flutter's Supabase URL and normal API endpoint remain unchanged.

## GitHub Actions configuration after approval

The local [workflow](../../.github/workflows/deploy-azure-workers.yml) validates on relevant PRs and main pushes. Deployment requires repository variable `AZURE_DEPLOY_ENABLED=true`, the main branch, and protected environment `azure-production`. No GitHub changes have been published. Create that environment with required reviewers and main-only branch rules before enabling deployment. Use a Microsoft Entra application/service principal **without a client secret** and the exact [federated credential](../../deploy/azure/github-federation.json). Its subject is `repo:Zalweb/Tabby:environment:azure-production` with audience `api://AzureADTokenExchange`. Assign Website Contributor at the specific app scope only; do not assign subscription Contributor or Key Vault secret permissions to CI.

Approved setup commands (identifiers are not credentials; capture outputs locally):

```powershell
az ad app create --display-name tabby-workers-github --query '{objectId:id,clientId:appId}' -o json
az ad sp create --id <client-id> --query id -o tsv
az ad app federated-credential create --id <application-object-id> --parameters @deploy/azure/github-federation.json -o none
az role assignment create --assignee-object-id <service-principal-object-id> --assignee-principal-type ServicePrincipal --role "Website Contributor" --scope <app-resource-id> -o none
```

Set repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_WEBAPP_NAME`, `AZURE_RESOURCE_GROUP`. These are nonsecret identifiers; runtime secrets stay in Key Vault. First deploy/verify the disabled package manually, finish live gates, enable workers, then set `AZURE_DEPLOY_ENABLED=true`. The workflow uses GitHub OIDC and Azure RBAC, never a publish profile or stored client secret. It tests on Node 24, deploys only the allowlisted package, then probes readiness and unauthenticated denial with bounded retries. GitHub environment protection is a server-side configuration and cannot be established by the YAML alone. See [Microsoft's OIDC deployment guide](https://learn.microsoft.com/en-us/azure/app-service/deploy-github-actions).

Rollback: disable worker execution and automatic deployment, stop external invokers, retain deployed revision/package evidence and deploy the last verified worker package. Do not roll back migrations or financial history. Stop/delete paid resources only under the applicable user authorization, accounting for persistent Key Vault protection and App Service plan billing.
