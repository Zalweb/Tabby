# Architecture and current baseline

## Current mobile source — 2026-11-13T16:25:00+08:00

The following source inspection supersedes the persistence claim in the retained foundation record below. Flutter/Riverpod/GoRouter and Supabase remain the application boundary. Android and iOS select [native ledger storage](../../lib/features/tabs/data/ledger_storage_factory_native.dart) through [LedgerCacheStorage](../../lib/features/tabs/data/ledger_cache_storage.dart). The integrated [Drift database](../../lib/features/tabs/data/ledger_cache_database.dart) uses SQLite3 Multiple Ciphers with ChaCha20, a secure-storage-held key, WAL/FULL synchronization, transactional imports and deletion tombstones. A missing key never overwrites an existing database. Legacy encrypted JSON is imported per key without deleting its source. Commands, mappings and cached history use this adapter; account-scoped media/form/PIN preferences also retain dedicated secure-storage records. This is implemented source, not merely a dependency or future plan, and does not imply every SDK-owned persistence layer uses the ledger database.

Current audit base is `80d72f3f48a874a81404671c46380d4e608379c0` plus the explicitly recorded dirty mobile patch. The production client still defaults to the original hosted Supabase endpoint. Azure is a separately restored self-hosted migration-test destination with copied original records, not a disposable database. The isolated Android debug package is `com.zalweb.tabby.usbtest`; production remains `com.zalweb.tabby`. Signup/schedulers/M2 gates stay disabled on the destination. See [QA-003 evidence](../verification/VER-QA-003-MOBILE.md), [restore evidence](../verification/VER-QA-002-AZURE-RESTORE.md) and [readiness inventory](../verification/PRODUCTION_READINESS_REPORT.md). These observations authorize no deployment or cutover.

## Foundation record (historical)

Flutter client uses Riverpod state and GoRouter, with Supabase Auth/PostgreSQL/Storage/Realtime. Current secure-storage JSON cache and queue are implemented; transactional Drift persistence remains a planned migration, not a completed foundation. Native Android entry uses FlutterFragmentActivity. iOS and web share core code and require regression checks for shared changes.

Source baseline: `d33d716a52461ce70c4f086bb20f4c68f3bd58d6`, app version 1.0.4+5 at foundation creation. Current schema/migrations are implementation sources; deployed database state is unverified here. Local config specifies PostgreSQL 17; verify deployed version before schema rollout rather than relying on historical PostgreSQL 15+ descriptions.

## Data boundaries

Authentication establishes current account/session generation. Commands flow from UI to application service to durable queue to versioned authenticated RPC. Server validates party membership, allocation sums, idempotency and legal state transitions. Results reconcile by operation/record IDs into local state. Signed attachment URLs are temporary views of durable storage objects.

The target ledger and payment interfaces are defined in [master plan](../plans/IMPLEMENTATION.md#shared-contracts). All financial writes must be atomic and audit preserving. Keep expense receipts distinct from payment proofs; recipient access is checked against the linked obligation/payment.

## Sources of truth

Committed migrations are ordered upgrade history. schema_all.sql is the synchronized installation snapshot. Neither establishes deployment. Project decisions establish intent; task/verification records establish tested behavior. Remote production metadata and acceptance evidence must be recorded separately.
