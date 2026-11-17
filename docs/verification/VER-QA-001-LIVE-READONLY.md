# VER-QA-001-LIVE-READONLY — Supabase read-only migration and API audit

```json verification-metadata
{
  "id": "VER-QA-001-LIVE-READONLY",
  "task_ids": [
    "QA-001",
    "SEC-002",
    "LED-003",
    "PAY-001",
    "PAY-004",
    "CAP-005"
  ],
  "checks": [
    { "category": "integration", "outcome": "failed" },
    { "category": "backend-integration", "outcome": "failed" },
    { "category": "backend-authorization", "outcome": "failed" },
    { "category": "anonymous-postgrest", "outcome": "passed" },
    { "category": "authenticated-postgrest", "outcome": "unverified" },
    { "category": "android-device", "outcome": "unverified" },
    { "category": "regression", "outcome": "unverified" }
  ],
  "timestamp": "2026-11-04T01:17:53+08:00",
  "tested_commit": "38635fdbd392acf9ce4d62759fb63afdaad2b257",
  "dirty_tree": true,
  "environment": "Windows PowerShell; Supabase Management API read-only SQL against project ziaqrkagsvozhotremsx (PostgreSQL 17.11, read-only DB role); PostgREST GET with publishable/anon key; no authenticated user JWT or attached Android device.",
  "commands": [
    "GET /v1/projects/ziaqrkagsvozhotremsx/database/migrations",
    "SELECT version, name FROM supabase_migrations.schema_migrations ORDER BY version",
    "SELECT public relation inventory from pg_catalog.pg_class/pg_namespace",
    "SELECT table_name, column_count, column_signature FROM information_schema.columns GROUP BY table_name ORDER BY table_name",
    "SELECT exact target signatures with to_regprocedure(...) IS NOT NULL",
    "SELECT target function security/grants with has_function_privilege",
    "SELECT schemaname,tablename,policyname,cmd,roles,qual,with_check FROM pg_catalog.pg_policies WHERE schemaname='public' ORDER BY tablename,policyname",
    "SELECT pubname,schemaname,tablename FROM pg_catalog.pg_publication_tables WHERE pubname='supabase_realtime' ORDER BY schemaname,tablename",
    "PostgREST GET /rest/v1/<table>?select=id&limit=0 and /rest/v1/rpc/<function>?<uuid-arguments>",
    "adb devices -l"
  ]
}
```

**Run:** 2026-11-04T01:17:53+08:00
**Task:** [QA-001](../progress/tasks/QA-001.md)
**Related tasks:** SEC-002, LED-003, PAY-001, PAY-004, CAP-002 through CAP-006, QR-002/003/005/006
**Agent/platform:** Codex root / Windows PowerShell
**Branch and source base:** `codex/m1-application-fixes` / `38635fdbd392acf9ce4d62759fb63afdaad2b257`
**Project:** `ziaqrkagsvozhotremsx` (Tabby; user-confirmed). No project credentials or user financial data are recorded here.

## Expected and actual results

Expected: live history and schema match the contract required by the current plan; anonymous routes are limited as specified; authenticated authorization and realtime contract metadata are present. Actual: history/schema parity failed (16 exact, 2 drifted, 30 absent); 28 required tables and eight named RPC signatures are absent; one sensitive helper still grants authenticated EXECUTE; anonymous probes only established limited endpoint behavior. No authenticated user or device acceptance was performed.

## Evidence

## Scope and safety

This was a live, read-only audit. Management API SQL calls used `POST /v1/projects/ziaqrkagsvozhotremsx/database/query/read-only`; all submitted SQL was `SELECT`. The migration list and key metadata were fetched with GET. PostgREST probes used GET and the publishable/anon key only. No rows containing user data were fetched: relation probes used `limit=0`; catalog queries returned schema metadata only. No Storage, Auth, DDL, DML, migration, configuration, deployment, schema-cache or release operation was performed.

The SQL session reported `current_database() = postgres`, `current_user = supabase_read_only_user`, `session_user = supabase_read_only_user`, `transaction_read_only = on`, and `server_version = PostgreSQL 17.11`. Project status from the Management API was `ACTIVE_HEALTHY`. A first connection attempt returned `ECONNREFUSED`; subsequent read-only calls succeeded. No authenticated end-user JWT was available. `adb devices -l` listed no devices.

## Migration classification

Local source inventory: `Get-ChildItem supabase/migrations -Filter *.sql | Sort-Object Name` returned 48 files. Remote history was queried with:

```sql
SELECT version, name
FROM supabase_migrations.schema_migrations
ORDER BY version;
```

The read-only endpoint returned these 18 rows:

| Remote version | Remote name | Local migration classification |
|---|---|---|
| 20260913000001 | core_schema | applied, exact |
| 20260913000002 | rls_policies | applied, exact |
| 20260913000003 | balance_functions | applied, exact |
| 20260913000004 | storage_and_triggers | applied, exact |
| 20260917000001 | authz_hardening | applied, exact |
| 20260917000002 | friend_code_requests | applied, exact |
| 20260917000003 | email_auth_profile_metadata | applied, exact |
| 20260917000004 | relationship_scope | applied, exact |
| 20260917000005 | payment_methods | applied, exact |
| 20260930161339 | 20260930000001_friendship_realtime_notifications | drifted: local version is 20260930000001 |
| 20260930161351 | 20260930000002_tab_reminders_realtime | drifted: local version is 20260930000002 |
| 20261029000001 | atomic_money_contract | applied, exact |
| 20261029000002 | participant_identity_hardening | applied, exact |
| 20261029000003 | money_integrity_hardening | applied, exact |
| 20261030000001 | production_reconciliation | applied, exact |
| 20261030000002 | restrict_unchecked_balance | applied, exact |
| 20261030000003 | drop_classroom_integration | applied, exact |
| 20261030000004 | authorization_hardening | applied, exact |

Exact-applied local migration files (16): `20260913000001_core_schema.sql`, `20260913000002_rls_policies.sql`, `20260913000003_balance_functions.sql`, `20260913000004_storage_and_triggers.sql`, `20260917000001_authz_hardening.sql`, `20260917000002_friend_code_requests.sql`, `20260917000003_email_auth_profile_metadata.sql`, `20260917000004_relationship_scope.sql`, `20260917000005_payment_methods.sql`, `20261029000001_atomic_money_contract.sql`, `20261029000002_participant_identity_hardening.sql`, `20261029000003_money_integrity_hardening.sql`, `20261030000001_production_reconciliation.sql`, `20261030000002_restrict_unchecked_balance.sql`, `20261030000003_drop_classroom_integration.sql`, `20261030000004_authorization_hardening.sql`. Drifted local files: `20260930000001_friendship_realtime_notifications.sql`, `20260930000002_tab_reminders_realtime.sql`; the remote version/name rows above have equivalent names but different version identifiers. Migration-history absent (30 files): `20261001000001_add_users_payment_columns.sql`, `20261001000002_is_phone_available_rpc.sql`, `20261031000001_restrict_pair_outstanding.sql`, `20261031000002_idempotent_money_commands.sql`, `20261031000003_contact_financial_parties.sql`, `20261031000004_atomic_group_creation.sql`, `20261031000005_money_amount_limits.sql`, `20261031000006_payment_decisions.sql`, `20261101000001_payment_proof_revisions.sql`, `20261101000002_expense_receipt_revisions.sql`, `20261101000003_payment_method_access.sql`, `20261101000004_atomic_payment_methods.sql`, `20261101000005_reminder_acceptance.sql`, `20261101000006_background_reminders.sql`, `20261101000007_canonical_profile_phones.sql`, `20261101000008_profile_writes.sql`, `20261101000009_profile_avatars.sql`, `20261101000010_connection_preferences.sql`, `20261102000001_private_account_export.sql`, `20261102000002_account_deletion_requests.sql`, `20261102000003_private_ledger_export_pages.sql`, `20261102000004_bilateral_expense_changes.sql`, `20261102000005_expense_revision_projection.sql`, `20261102000006_group_contact_expense_changes.sql`, `20261102000007_ledger_read_pages.sql`, `20261102000008_reviewed_account_anonymization.sql`, `20261102000009_custom_splits.sql`, `20261102000010_recurring_obligations.sql`, `20261102000011_explicit_contact_claims.sql`, `20261102000012_expense_review.sql`. Thus the history comparison is 16 exact / 2 version-drifted / 30 absent, with no additional remote history rows. “Absent” here means absent from `schema_migrations`; it does not alone prove every statement/object in a file is absent.

## Live schema object inventory

Relation query:

```sql
SELECT n.nspname AS schema_name, c.relname AS relation_name,
       c.relkind AS relation_kind, c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','f')
ORDER BY c.relkind,c.relname;
```

Returned rows (all `relkind=r`, `rls_enabled=true`, `rls_forced=false`): `activity_logs`, `contacts`, `friendships`, `group_members`, `group_permissions`, `groups`, `notifications`, `payment_methods`, `payment_proofs`, `payments`, `recurring_rules`, `reminders`, `reports`, `tab_members`, `tabs`, `transaction_participants`, `transactions`, `users`.

Column query:

```sql
SELECT table_name,count(*) AS column_count,
       string_agg(column_name||':'||udt_name||CASE WHEN is_nullable='NO'
         THEN ' NOT NULL' ELSE ' NULL' END,', ' ORDER BY ordinal_position) AS column_signature
FROM information_schema.columns WHERE table_schema='public'
GROUP BY table_name ORDER BY table_name;
```

Returned rows (exact column signatures):

| Relation | Count | Returned signature |
|---|---:|---|
| activity_logs | 9 | id:uuid NOT NULL, actor_user_id:uuid NOT NULL, tab_id:uuid NULL, transaction_id:uuid NULL, payment_id:uuid NULL, group_id:uuid NULL, event_type:text NOT NULL, metadata:jsonb NOT NULL, created_at:timestamptz NOT NULL |
| contacts | 9 | id:uuid NOT NULL, owner_user_id:uuid NOT NULL, display_name:text NOT NULL, phone:text NULL, email:text NULL, claimed_user_id:uuid NULL, claim_status:text NOT NULL, created_at:timestamptz NOT NULL, claimed_at:timestamptz NULL |
| friendships | 6 | id:uuid NOT NULL, requester_id:uuid NOT NULL, addressee_id:uuid NOT NULL, status:text NOT NULL, created_at:timestamptz NOT NULL, responded_at:timestamptz NULL |
| group_members | 6 | id:uuid NOT NULL, group_id:uuid NOT NULL, user_id:uuid NOT NULL, role:text NOT NULL, status:text NOT NULL, joined_at:timestamptz NOT NULL |
| group_permissions | 4 | id:uuid NOT NULL, group_id:uuid NOT NULL, permission_key:text NOT NULL, enabled:bool NOT NULL |
| groups | 7 | id:uuid NOT NULL, created_by:uuid NOT NULL, name:text NOT NULL, description:text NULL, avatar_url:text NULL, created_at:timestamptz NOT NULL, updated_at:timestamptz NOT NULL |
| notifications | 12 | id:uuid NOT NULL, recipient_user_id:uuid NOT NULL, notification_type:text NOT NULL, related_tab_id:uuid NULL, related_transaction_id:uuid NULL, related_payment_id:uuid NULL, related_group_id:uuid NULL, title:text NOT NULL, body:text NOT NULL, is_read:bool NOT NULL, created_at:timestamptz NOT NULL, read_at:timestamptz NULL |
| payment_methods | 10 | id:uuid NOT NULL, owner_user_id:uuid NOT NULL, provider:text NOT NULL, display_name:text NOT NULL, account_label:text NOT NULL, qr_storage_path:text NULL, is_active:bool NOT NULL, is_default:bool NOT NULL, created_at:timestamptz NOT NULL, updated_at:timestamptz NOT NULL |
| payment_proofs | 6 | id:uuid NOT NULL, payment_id:uuid NOT NULL, file_url:text NOT NULL, file_name:text NOT NULL, mime_type:text NOT NULL, uploaded_at:timestamptz NOT NULL |
| payments | 11 | id:uuid NOT NULL, tab_id:uuid NOT NULL, submitted_by:uuid NOT NULL, amount_centavos:int8 NOT NULL, payment_method:text NOT NULL, note:text NULL, status:text NOT NULL, submitted_at:timestamptz NOT NULL, confirmed_by:uuid NULL, confirmed_at:timestamptz NULL, recipient_user_id:uuid NULL |
| recurring_rules | 13 | id:uuid NOT NULL, created_by:uuid NOT NULL, tab_id:uuid NOT NULL, frequency:text NOT NULL, amount_centavos:int8 NOT NULL, start_date:date NOT NULL, end_date:date NULL, has_end_date:bool NOT NULL, active:bool NOT NULL, category:text NOT NULL, description:text NOT NULL, created_at:timestamptz NOT NULL, updated_at:timestamptz NOT NULL |
| reminders | 9 | id:uuid NOT NULL, transaction_id:uuid NOT NULL, created_by:uuid NOT NULL, recipient_user_id:uuid NOT NULL, reminder_type:text NOT NULL, scheduled_for:timestamptz NOT NULL, sent_at:timestamptz NULL, status:text NOT NULL, repeat_interval_minutes:int4 NULL |
| reports | 11 | id:uuid NOT NULL, reported_by:uuid NOT NULL, tab_id:uuid NULL, transaction_id:uuid NULL, payment_id:uuid NULL, report_type:text NOT NULL, message:text NOT NULL, status:text NOT NULL, resolution_note:text NULL, created_at:timestamptz NOT NULL, resolved_at:timestamptz NULL |
| tab_members | 6 | id:uuid NOT NULL, tab_id:uuid NOT NULL, user_id:uuid NULL, contact_id:uuid NULL, role:text NOT NULL, joined_at:timestamptz NOT NULL |
| tabs | 8 | id:uuid NOT NULL, tab_type:text NOT NULL, status:text NOT NULL, group_id:uuid NULL, user_a:uuid NULL, user_b:uuid NULL, created_at:timestamptz NOT NULL, updated_at:timestamptz NOT NULL |
| transaction_participants | 9 | id:uuid NOT NULL, transaction_id:uuid NOT NULL, user_id:uuid NULL, contact_id:uuid NULL, participant_role:text NOT NULL, share_amount_centavos:int8 NOT NULL, share_percentage:numeric NULL, acknowledged:bool NOT NULL, acknowledged_at:timestamptz NULL |
| transactions | 15 | id:uuid NOT NULL, tab_id:uuid NOT NULL, created_by:uuid NOT NULL, recurring_rule_id:uuid NULL, transaction_type:text NOT NULL, category:text NOT NULL, description:text NOT NULL, total_amount_centavos:int8 NOT NULL, currency:text NOT NULL, transaction_date:date NOT NULL, due_date:date NULL, status:text NOT NULL, created_at:timestamptz NOT NULL, updated_at:timestamptz NOT NULL, receipt_url:text NULL |
| users | 11 | id:uuid NOT NULL, email:text NULL, phone:text NULL, display_name:text NOT NULL, avatar_url:text NULL, created_at:timestamptz NOT NULL, updated_at:timestamptz NOT NULL, friend_code:text NOT NULL, gcash_number:text NULL, maya_number:text NULL, qr_code_url:text NULL |

Cross-checking local `CREATE TABLE` definitions in the 48 migrations against `to_regclass`/the catalog inventory found 18 existing public tables and these 28 absent tables: `account_deletion_objects`, `account_deletion_requests`, `connection_operations`, `connection_preferences`, `contact_claim_invitations`, `expense_acknowledgments`, `expense_change_decisions`, `expense_change_outputs`, `expense_change_requests`, `expense_change_results`, `expense_change_reviewers`, `expense_dispute_resolutions`, `expense_disputes`, `expense_resolution_votes`, `expense_split_details`, `financial_operations`, `group_creation_commands`, `m2_feature_flags`, `payment_decisions`, `payment_method_operations`, `payment_method_revisions`, `push_delivery_jobs`, `push_device_bindings`, `recurrence_events`, `recurrence_occurrences`, `recurrence_rules`, `reminder_operations`, `transaction_receipt_revisions`. These object results are absence from the live public schema, not just migration-history absence.

Target `to_regprocedure` query and returned rows:

```sql
SELECT x.signature, to_regprocedure(x.signature) IS NOT NULL AS exists
FROM (VALUES
 ('public.get_net_balance(uuid,uuid)'),
 ('public.get_pair_outstanding(uuid,uuid,uuid)'),
 ('public.create_expense_v1(uuid,jsonb)'),
 ('public.submit_payment_v1(uuid,jsonb)'),
 ('public.expense_review_state_v1(uuid)'),
 ('public.review_expense_v1(uuid,jsonb)'),
 ('public.change_payment_method_v1(uuid,jsonb)'),
 ('public.materialize_recurrence_v1(uuid,jsonb)'),
 ('public.reject_payment_v1(uuid,text)'),
 ('public.request_expense_change_v2(uuid,uuid,text,bigint,text,uuid,boolean)')
) AS x(signature) ORDER BY 1;
```

Rows: `get_net_balance(uuid,uuid)=true`; `get_pair_outstanding(uuid,uuid,uuid)=true`; all other eight listed signatures returned `false`. Separately, the live public catalog contains 42 functions; a source-name scan found 132 names in checked-in `CREATE FUNCTION` definitions (name scan can include overloads/duplicates and is only a summary). The above signature probes are the exact API contract result for the named functions.

## Authorization and PostgREST probes

Function inventory query:

```sql
SELECT p.oid::regprocedure::text AS signature, p.prosecdef AS security_definer,
       p.provolatile AS volatility,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('get_net_balance','get_pair_outstanding','create_expense_atomic','create_expense_v1',
  'submit_payment','submit_payment_v1','confirm_payment','list_payment_methods_for_tab')
ORDER BY 1;
```

Returned rows:

| Signature | Definer | Volatility | anon EXECUTE | authenticated EXECUTE |
|---|---:|---|---:|---:|
| confirm_payment(uuid) | true | volatile | false | true |
| create_expense_atomic(uuid,text,text,bigint,uuid,jsonb,date,text) | true | volatile | false | true |
| get_net_balance(uuid,uuid) | true | stable | false | true |
| get_pair_outstanding(uuid,uuid,uuid) | true | stable | false | true |
| list_payment_methods_for_tab(uuid,uuid) | true | stable | false | true |
| submit_payment(uuid,uuid,uuid,bigint,text,text) | true | volatile | false | true |

`pg_get_functiondef('public.get_pair_outstanding(uuid,uuid,uuid)'::regprocedure)` returned a SECURITY DEFINER body that accepts caller-supplied tab/debtor/payee IDs and contains no `auth.uid()` or `is_tab_member` check. The authenticated role has EXECUTE. Anonymous direct GET to `/rest/v1/rpc/get_pair_outstanding` with placeholder UUIDs returned HTTP 401, SQLSTATE `42501`, `permission denied for function get_pair_outstanding`. This proves anon denial only; no authenticated-user RPC was called. Checked-in `supabase/migrations/20261031000001_restrict_pair_outstanding.sql` contains:

```sql
REVOKE ALL ON FUNCTION public.get_pair_outstanding(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
```

That migration is absent from remote history and the live authenticated grant disagrees with intended client denial. SEC-002 backend authorization must remain open; do not invoke the helper or change production as part of this audit.

Anonymous PostgREST GET with the publishable key and `?select=id&limit=0` returned HTTP 200, zero rows and `content-range: */*` for `transactions`, `users`, `tabs`, `groups`, `group_members`, `payments`, and `payment_methods`. This only verifies endpoint/schema-cache availability; zero-limit requests do not prove row-level filtering. The same GET for `expense_change_requests` and `m2_feature_flags` returned HTTP 404 / `PGRST205` (“Could not find table ... in schema cache”), consistent with the catalog absence. Direct anon RPC GETs to `get_net_balance` and `get_pair_outstanding` returned HTTP 401 / `42501 permission denied for function`. No authenticated-role JWT was available, so positive-member and outsider row-boundary checks remain unrun. The PostgREST root OpenAPI request returned “Secret API key required”; the secret key was not used.

RLS/policy inventory query:

```sql
SELECT schemaname,tablename,policyname,cmd,roles,qual,with_check
FROM pg_catalog.pg_policies WHERE schemaname='public'
ORDER BY tablename,policyname;
```

It returned 60 policy rows across the 18 relations; every returned `roles` value was `{authenticated}`. Relevant returned rows include: `transactions` INSERT, `Tab members can insert transactions`, check `(created_by = auth.uid()) AND is_tab_member(tab_id, auth.uid())`; `transactions` SELECT, `Tab members can view transactions`, using `is_tab_member(tab_id, auth.uid())`; `transaction_participants` UPDATE, `Participants or tab members can update participant status`, using/check `user_id = auth.uid()`; `payments` SELECT, `Tab members can view payments`, using `is_tab_member(tab_id, auth.uid())`; `payment_methods` SELECT, `Owners can view their payment methods`, using `owner_user_id = auth.uid()`. `payment_methods` has no direct friend/debtor SELECT policy in this inventory. Catalog policy definitions are not end-to-end role behavior; authenticated HTTP boundary checks are still required.

Realtime query:

```sql
SELECT pubname,schemaname,tablename
FROM pg_catalog.pg_publication_tables
WHERE pubname='supabase_realtime'
ORDER BY schemaname,tablename;
```

Returned 12 rows: `public.activity_logs`, `public.friendships`, `public.group_members`, `public.groups`, `public.notifications`, `public.payment_proofs`, `public.payments`, `public.tab_members`, `public.tabs`, `public.transaction_participants`, `public.transactions`, `public.users`. Tracked migration source has explicit publication statements only for notifications and transaction_participants. Other live memberships are not represented by tracked migration statements; classify them as untracked live drift pending provenance review, not as proof of a failed runtime subscription.

## Limits and next action

**Live migration/schema gate: failed.** 30 migration-history entries are absent, two versions drift, 28 expected tables are absent, and eight named v1 contract RPCs are absent. Existing table columns show older contracts, including the 10-column `payment_methods`, 6-column `payment_proofs`, 11-column `payments`, and 13-column `recurring_rules`.

**Backend authorization gate: failed/open.** Authenticated EXECUTE remains on the unchecked `get_pair_outstanding` SECURITY DEFINER helper, and no authenticated JWT boundary check ran. The M2 contract/API surfaces are not deployed, so the live M2 journey gate remains open and rollout flags remain off.

**Anonymous public surface: partial.** Anonymous function denial and absent-table responses were observed. Zero-limit table reads are not authorization acceptance. Authenticated RLS behavior is unverified.

**Device gate: open.** `adb devices -l` returned no attached devices; no physical-device journey ran.

No task is promoted to verified or complete by this evidence. Next action: in a disposable Supabase project, reconcile migration history and fresh/upgrade schema, then use two authenticated fixture accounts for read-only positive/negative authorization checks and the planned API journeys; separately attach a supported Android device and run the device matrix. Do not apply these migrations to the production project as part of this audit.
