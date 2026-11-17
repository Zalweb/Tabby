# QA-002 Azure restore, upgrade and live services

```json verification-metadata
{
  "id": "VER-QA-002-AZURE-RESTORE",
  "task_ids": ["QA-002"],
  "timestamp": "2026-11-13T11:35:00+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Real East Asia Azure VM and private Blob; PostgreSQL17.11/PostgREST16.5/GoTrue2.197/Storage1.89.12; source Supabase project read-only; Windows Node26/Azure CLI2.92. No production endpoint cutover.",
  "commands": [
    "node scripts/azure-full-prepare-export.cjs; protected Azure Run Command export-source.py",
    "restore-source.py (rollback/full parity, then --commit)",
    "node scripts/azure-full-prepare-upgrade.cjs; upgrade-source.py (rollback, then --commit)",
    "transfer-backup.py; local DPAPI recovery and node scripts/azure-full-verify-backup.cjs",
    "restore-assets.py through HTTPS Storage API with identity/ownership reconciliation",
    "configure-application.py; configure-smtp.py; explicit own-address SMTP test",
    "live-acceptance.py with real GoTrue-issued tokens and synthetic accounts",
    "node --test scripts/usb-test.test.cjs scripts/azure-full-template.test.cjs scripts/azure-full-seal.test.cjs scripts/azure-full-prepare-export.test.cjs"
  ],
  "checks": [
    {"category":"consistent-source-export","outcome":"passed"},
    {"category":"migration-rehearsal","outcome":"passed"},
    {"category":"restored-data-parity","outcome":"passed"},
    {"category":"immutable-financial-upgrade","outcome":"passed"},
    {"category":"private-media-restore","outcome":"passed"},
    {"category":"off-vm-backup-recovery","outcome":"passed"},
    {"category":"live-backend","outcome":"passed"},
    {"category":"realtime-owner-update","outcome":"passed"},
    {"category":"smtp-own-recipient","outcome":"passed"},
    {"category":"google-oauth-journey","outcome":"unverified"},
    {"category":"firebase-push-delivery","outcome":"unverified"},
    {"category":"production-cutover","outcome":"unverified"},
    {"category":"integration-review","outcome":"unverified"}
  ]
}
```

## Expected and actual results

### Source export and exact restore

The user supplied the connection in an ignored local file. A duplicate untracked credential note was moved intact to ignored storage. No password or private record was printed or committed. The initial native connection failed CA verification. Downloaded the certificate from the official Studio-configured HTTPS URL, pinned SHA256 fingerprint `80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA`, retained `verify-full`, and connected successfully. See [Supabase TLS guidance](https://supabase.com/docs/guides/platform/ssl-enforcement).

Run `run-20261113T025405594z` used PostgreSQL17.11 tools, pinned official CLI3.1.0 schema/data/reserved-role filters and one exported repeatable-read snapshot for schema/data and fingerprints. Counts:7 Auth users,3 expenses,0 payments,53 table fingerprints. Filtered roles/schema/data sizes were358/135539/53560 bytes. A first rollback rehearsal failed on the missing managed Vault namespace; adding the namespace inside the transaction resolved it. The full rollback rehearsal and committed restore both matched all53 count/content fingerprints, with zero mismatches. Original source remained read-only and active.

### Reconciliation and upgrade

Fresh source inventory contained18 migration rows,7 custom Storage policies,1 Auth-to-public trigger,1 public event trigger, and zero Vault secrets. The two remote September versions `20260930161339`/`20260930161351` were compared with local `20260930000001`/`20260930000002`: SQL matched after comment/whitespace normalization. Original versions/names/statements were retained, without replay or rename. Restored custom policies, Auth trigger, event trigger and Realtime publication members that the filtered schema export excludes.

The first large command payload was not delivered: no driver/capsule/report appeared on the VM. Compressing the plaintext before encryption reduced transport size, and the retry executed. All32 genuinely pending migrations passed a single rollback rehearsal and then committed, reaching50 history rows through20261104000002. Transaction wrappers were removed only at reviewed file boundaries so rehearsal could roll back the entire upgrade. Source-projected original transactions, participants and payments passed exact count/content invariants after upgrade. No confirmed original financial row was rewritten.

### Media, backup and providers

Created `sttabby7abf436e20261113` Standard LRS private Blob storage with public blobs disabled and HTTPS/TLS1.2 minimum. Sealed database/media/key-recovery packages were transferred using short-lived scoped grants, never plaintext exports. Downloaded the encrypted database/key-recovery packages onto this computer; current-user Windows DPAPI protected the recovery private key. An independent local decrypt/recovery verified all3 dump file hashes and53-table manifest. The captured database backup is45439 encrypted bytes. This is a verified rehearsal backup, not scheduled backup/DR automation; recovery depends on this Windows user's DPAPI material, which still needs owner-managed secure retention.

VM requests through its public IP first failed TLS transport during media POSTs; local resolution of its own valid HTTPS hostname avoided that hairpin while retaining certificate verification. Storage then reported missing role membership. Granted Storage admin membership in the existing anon/authenticated/service_role API roles, matching its per-request role-switching requirement; policies/TLS stayed enabled. All3 original media files were copied through the Storage API, re-downloaded and SHA256 checked; original object IDs, owner/owner_id, created timestamps and metadata were reconciled. Backend version/update fields needed by the destination filesystem remain destination-managed.

Installed all3 actual repository Edge functions and destination-generated worker secrets. Ordinary users are denied. No schedulers were enabled. Fresh source function inventory returned no deployed functions; no existing source worker was retired. Firebase service credentials/delivery remain unconfigured. Copied existing Google provider credentials/settings privately; browser/native callback acceptance remains unverified.

Azure's current [retirement guide](https://learn.microsoft.com/en-us/azure/communication-services/acs-retirement-and-breaking-changes-guide) disallows new email onboarding, so no Communication resource/application was created. Its provider was registered during investigation. User chose own-address email testing and supplied a Resend key in an ignored file. SMTP STARTTLS with certificate validation/authentication passed. A single requested own-address test was accepted, and the user confirmed inbox arrival. Signup stays disabled. [Resend's test sender](https://resend.com/docs/knowledge-base/403-error-resend-dev-domain) cannot email arbitrary users without a verified domain; full production email remains a cutover gate.

### Live acceptance and limits

The successful run passed26 checks with3 synthetic Admin-created accounts and real GoTrue password-issued tokens: profile trigger, integer expense, same-operation replay, changed-payload denial, outsider read/write denial, private pair-helper privilege, stable fractional-input error, pending submission preserving balance, payer confirmation denial, concurrent recipient confirmations producing200/400 without overpayment, exact settlement, owned private-image upload/read, outsider media denial and all3 worker denials. Original3 transactions/6 participant rows were compared after fixture journeys and remained unchanged; original payments were empty. Synthetic rows are additional append-only test history on the destination, distinct from the migrated originals.

Initial live runs exposed the Storage role issue and two harness assumptions: a partial membership index cannot use an unqualified conflict target, and reminder-push correctly returns401 rather than the other workers'403. Corrected the harness and reran; the successful26-check result supersedes those failures. No product policy was relaxed to make tests pass.

Ignored evidence: `source-export-result-2.txt`, `restore-parity-rehearsal.txt`, `restore-committed-result.txt`, `upgrade-rehearsal-result-2.txt`, `upgrade-committed-result.txt`, `backup-transfer-result.txt`, `media-role-repair-result.txt`, `application-config-result.txt`, `smtp-config-result.txt`, `own-email-test-result.txt`, `live-acceptance-passed-result.txt` under `.dart_tool/azure-full/`. Source and new backend remain separate; final write freeze/delta synchronization, production client rollout, Google/email-to-other-users/FCM/Realtime and full device/release/independent-review gates remain open. Base hosting estimateUSD46.85/month plus Blob/operations/egress; existing USD100 student spending limit and USD90 alert budget remain in force.

## Evidence

The ignored artifacts listed above contain sanitized run results. Protected SQL/fingerprints/backup manifests remain root-only on the VM under the recorded run ID; sealed database/media/key-recovery packages also exist in private Blob and ignored local storage. Reproducible source and operating limits are in [deployment tools](../../deploy/azure-full/README.md). No secrets, original financial rows, private images or fixture passwords appear in shared records. Local host regressions passed27/27; Python9-file and shell syntax checks passed. The tablet live suite subsequently passed using real Auth over explicitly authorized paired Wi-Fi; physical evidence is recorded separately.

## Limits and next action

Finish physical smoke/matrix acceptance, independently review/integrate the uncommitted changes and retain recovery material securely. Establish production email, verify Google/Realtime/provider journeys, then agree the final write freeze/delta reconciliation and production client rollout. Original source/client endpoint remains active; this evidence establishes a validated live migration-test backend, not production cutover or QA-001/REL-001 completion. Schedulers/signup/M2 remain disabled, Firebase delivery and fresh bootstrap remain unverified.

### 2026-11-13T11:57:06.621+08:00 ? Physical suites and Realtime supersede pending checks

The user-authorized paired-Wi-Fi live, native smoke and scripted device matrix all passed. The final expanded live run also verified delivery of a real Azure Postgres UPDATE to the tablet after explicit replication readiness, with a tagged synthetic profile restored afterward. See [tablet evidence](VER-QA-002-WIFI-TABLET.md). No full lifecycle/cross-user Realtime or release acceptance is inferred from this owner-update check.
