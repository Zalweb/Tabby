# Full Azure Supabase destination

Owner: [QA-002](../../docs/progress/tasks/QA-002.md); hosting decision: [DEC-012](../../docs/project/DECISIONS.md#dec-012--stage-the-full-supabase-backend-on-azure-before-cutover).

The destination is live in `rg-tabby-backend-eastasia`, VM `tabby-supabase` (`Standard_B2als_v2`,2vCPU/4GB,64GB Standard SSD). API origin: `https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com`. Superseding2026-11-13: the original7 Auth users/3 expenses/0 payments and3 media objects are imported,53 snapshot fingerprints matched, and32 reconciled pending migrations reached50 history rows. Real Auth/finance/Storage/worker-denial checks passed26/26 with additional synthetic fixtures. See [restore/live evidence](../../docs/verification/VER-QA-002-AZURE-RESTORE.md). The Flutter production endpoint and original project remain unchanged; this is the live migration-test destination, with signup and schedulers disabled.

## Deployment and configuration

`scripts/azure-full-template.cjs` generates ARM from an ignored local JSON containing an Ed25519 **public** SSH key, DNS label, region and reviewed VM size. Credentials are generated only on the VM. Ingress allows TCP80/443 for TLS/ACME; SSH/database ports are not exposed. PostgreSQL/pooler host bindings are removed. Public dashboard access requires separate random Basic Auth. Signup is disabled during migration. Do not publish `.env`, local config, keys, raw command logs or exported customer media.

```powershell
node scripts/azure-full-template.cjs .dart_tool/azure-full/deployment-config.json .dart_tool/azure-full/main.json
# Fresh destination only: validate, then create using the authorized subscription.
az deployment group validate --resource-group rg-tabby-backend-eastasia --template-file .dart_tool/azure-full/main.json
az deployment group create --resource-group rg-tabby-backend-eastasia --name <unique-run-name> --template-file .dart_tool/azure-full/main.json
node scripts/azure-full-probe.cjs https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com .dart_tool/azure-full/public-config.json
```

Use the workspace-local CLI at `.dart_tool/azure-cli/sdk/bin/az.cmd` if `az` is not on PATH. Do not casually redeploy changed cloud-init over the existing VM: customData is provisioning data, not an application update mechanism. Never delete/reinitialize its persistent database to resolve a configuration problem. The OS disk detaches rather than deleting if the VM is removed; detached disks still incur charges and require explicit data-retention/cleanup handling.

Bootstrap pins official self-hosted release `self-hosted/v0.8.4`, commit`189adda99d1b56da55fc5a6ee3f849354aaea92a`. Private overrides pin PostgreSQL`17.11.0.019` (runtime17.11) and PostgREST16.5, matching the source minor and existing HTTP acceptance runtime. The prepared database image required explicit upstream platform initialization, service-password synchronization, Auth object ownership and the `graphql_public` namespace before services became healthy. The initial cloud-init failure remains in its logs; recovery was performed without deleting data. Current container health passed; a completely fresh cold run of the revised bootstrap is still unverified. GraphQL behavior is not established by creating its namespace.

## Costs and limits

Verified public retail estimates in East Asia: compute USD0.0526/hour, E6/64GB SSD USD4.80/month, static IPv4 USD0.005/hour. At730 hours these base items total approximately **USD46.85/month**. Disk operations/mount features, egress and backups can add cost. This is not an all-in price or a promise of indefinite hosting within the user's USD100 total credit.

The subscription spending limit is verified On. `tabby-credit-guard` is a USD90 annual Cost Management budget,2026-11-01 to2027-11-01, with actual-cost thresholds50/75/90/100% to the signed-in owner. Alerts do not stop consumption and can lag; they supplement the student's existing spending limit. No conversion to paid billing or automatic shutdown of production was configured. Exact remaining credit/expiry still needs confirmation. See [inventory](../../docs/verification/VER-QA-002-AZURE-INVENTORY.md).

## Source export and migration

The source is PostgreSQL17.11 with18 applied migrations, not the repository's50. Reconcile actual versions/statements before applying pending files. The latest read-only source inventory counted7 Auth users,3 expenses,0 payments and3 Storage objects; these are sanitized counts, not a restored-data claim.

The source database connection belongs in ignored `.env.azure-migration` as `SUPABASE_DB_URL=...`. Obtain it from Supabase Connect using a direct or session-pooler URI and the existing database password. Do not paste it into chat, pass it in command-line arguments, or reset the password without assessing existing connections.

`scripts/azure-full-export-assets.ps1` uses the existing management authorization to download private Storage objects and provider configuration, seals the snapshot in memory with the destination RSA public key and AES256-GCM, and writes only encrypted data into ignored storage. Source object ownership/metadata and SHA256 are retained for later reconciliation. It does not export database/Auth/financial rows and is not a consistent final cutover backup. Invoke Windows PowerShell with a process-only execution-policy override when local script policy requires it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/azure-full-export-assets.ps1
```

The encrypted rehearsal snapshot is `.dart_tool/azure-full/source-assets-20261113.sealed.json` (3 objects). Media is now restored and SHA256/identity/ownership verified. The database backup and separately wrapped key-recovery package are also held in private Standard LRS Blob account `sttabby7abf436e20261113`, container `migration-private`, and ignored local storage. Independent local key recovery verified all3 dump hashes. Recovery private material is protected by this Windows user's DPAPI; owner-managed secure retention and scheduled backups remain open. Do not remove the VM, disk, Windows profile or DPAPI material before an independent recovery arrangement is verified.

## Protected migration tools and current services

`azure-full-prepare-export.cjs` requires Node26, privately reads `.env.azure-migration`, downloads/hash-checks official CLI3.1.0 filters and the official CA, and prepares an encrypted capsule. `export-source.py` uses native container tools with read-only source connections and one exported snapshot. It stores root-only dumps/fingerprints and a sealed backup. `restore-source.py` defaults to rollback, checks dump integrity and an empty destination, then requires a full-parity rehearsal before `--commit`. Never rerun a committed restore over existing data.

`azure-full-prepare-upgrade.cjs` captures source custom policies/triggers/publications/history, verifies the two migration aliases and seals compressed pending SQL. `upgrade-source.py` restores those custom platform objects and18 original history rows, then applies only32 genuinely pending migrations. Its default is a single rollback transaction; commit requires the same packet's successful rehearsal and original financial invariants. It refuses unexpected inner transaction markers. These are reviewed migration operations, not an automatic production deploy pipeline.

`restore-assets.py` uses the authenticated Storage HTTP protocol, verifies downloaded bytes and reconciles original object identity/ownership. `transfer-backup.py` transfers only sealed packages with short-lived private Blob grants; `azure-full-verify-backup.cjs` independently verifies off-VM recovery using a private key supplied on stdin. Raw exports/keys/configuration/output stay private and Git-ignored.

Three actual repository Edge functions are installed; destination worker secrets are generated privately. Schedulers stay off, M2 stays disabled, Firebase push credentials/delivery remain unconfigured. The source has no deployed Edge functions. Google provider credentials were copied privately; native/browser OAuth and callback allowlisting still need acceptance. `live-acceptance.py` exercises only tagged synthetic accounts through real GoTrue-issued tokens and app-role HTTP requests, retaining synthetic financial history. Its latest run passed26 checks and preserved the original migrated financial rows.

Resend SMTP is configured through ignored `.env.azure-smtp.json` and encrypted `azure-full-prepare-smtp.cjs`/`configure-smtp.py` transfer. STARTTLS/auth and the requested own-address test email passed; the user confirmed inbox arrival. No new Azure Communication Email resource was created after checking its onboarding retirement. The test sender is restricted to the Resend account owner; a verified sending domain is required for other users. No new key input is currently needed.

Physical live/smoke/scripted matrix and owner-update Realtime delivery passed through the user's explicitly authorized paired Wi-Fi transport. Next verify full provider and cross-user/lifecycle Realtime journeys, establish production email and backup ownership, and plan the final write freeze/delta synchronization and client rollout. Original source writes after the snapshot are not yet synchronized. Do not mark QA-001/REL-001 complete or redirect published clients from platform/fixture probes alone.
