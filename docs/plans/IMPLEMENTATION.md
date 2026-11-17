# Master implementation plan

## Milestones

| Milestone | Deliverable | Gate |
|---|---|---|
| M0 | Root instructions, indexed plans, complete audit mapping, task/evidence records and CI checks | DOC-001 accepted; every finding mapped |
| M1 | Reliable existing Android core including audited corrections | No open P1 in exposed features; required integration/device/backend checks pass; limitations disclosed |
| M2 | Custom splits, tax/service charges, recurrence, explicit claiming and richer acknowledgment/proposal/dispute workflows | Each feature passes its acceptance suite before UI/marketing exposure |
| M3 | Exact signed candidate verified and authorized for release | Candidate commit/digest/certificate, upgrade tests, migration status and release evidence recorded |

## Shared contracts

- PartyRef = {kind: user | contact, id}; groups contain parties and cannot pay/receive.
- Expense command = stable operation ID, tab ID, actual payer, integer total, explicit per-party shares, dates and attachment references. Server validates unique parties, membership and exact sums.
- Payment model retains payer AND recipient, submission ID, amount, saved method reference/provider, status, timestamps and proofs in SQL/cache/UI. Separate submit, confirm, reject and record-received commands.
- Versioned RPCs enforce actor-scoped operation uniqueness. Same ID/same payload returns original result; same ID/different payload returns conflict. Confirmation locks the pair before checking outstanding amount.
- Sync results: queued, syncing, synced, retryableFailure, needsAttention. One executor owns online/replay writes; network availability is not synchronization.
- Attachments retain durable object/reference plus pending-upload state. URLs expire and are refreshed; proof revisions remain append-only.
- Every result is account/session-generation scoped; discard it after session change. Server checks authorization regardless of UI.

## Execution and ownership

M0 precedes implementation. Settle shared interfaces, then backend integrity and durable client sync, then dependent groups/payments/UI. Independent auth/platform/profile work may proceed once file ownership is agreed. Integration owner serializes providers/models/router/dependency/schema/workflow edits. Each task has an owner role and dependency IDs; actual agent claims live in task metadata/history.

Area plans: [ledger-and-sync](ledger-and-sync.md), [groups-and-expenses](groups-and-expenses.md), [payment-methods-and-qr](payment-methods-and-qr.md), [settlement-and-receipts](settlement-and-receipts.md), [security-and-privacy](security-and-privacy.md), [onboarding-and-auth](onboarding-and-auth.md), [home-and-notifications](home-and-notifications.md), [profile-and-connections](profile-and-connections.md), [android-and-release](android-and-release.md), [missing-capabilities](missing-capabilities.md).

## Compatibility and data repair

Use additive versioned RPCs and migrations; keep compatible reads and explicitly reject unsupported legacy financial writes. Never rename applied migrations. Keep schema_all.sql synchronized. Test fresh install and upgrade against deployed version inventory. Do not rewrite historical records by name/amount similarity: produce a reconciliation report and apply explicit audit-preserving corrections to unambiguous records only.

No production deployment, account mutation or public publication is performed by M0. Future agents follow actual session authorization and release gates.

## Release and rollback gates

Run migrations on disposable/local DB, then staging; verify effective grants, functions and policies as authenticated users. Record forward repair and compatibility rollback before deployment. Full Flutter analysis/tests, behavioral SQL acceptance (including concurrency), applicable web/workflow checks and device acceptance must pass on exact candidate. Debug-signed builds cannot enter publication. Preserve existing iOS/web behavior for shared-code changes.

Record permission denial, reboot, closed-app notification/tap, picker process death, gesture back, large text, account switching, offline response loss, QR update/expiry and signed upgrade results. Check native 16 KB compatibility. If access is unavailable, leave the check unverified and release gate open.

M2 tasks remain hidden until verified. Documentation and support/marketing copy must match exposed capability. A build alone is not release approval.

## Coordination and release tasks

- [INT-001](../progress/tasks/INT-001.md): integration owner freezes shared interfaces and behavioral contract fixtures before area agents edit dependent code.
- [QA-001](../progress/tasks/QA-001.md): verify all M1 journeys and real backend/device acceptance.
- [REL-001](../progress/tasks/REL-001.md): validate the exact signed artifact and record release handoff. M1 may release before M2; exposed M2 features must also be complete.

2026-11-17T10:11:55.271Z ? [QA-029 UI feedback audit](ui-feedback-audit.md) adds shared active-sheet feedback and lower-right Add with three centered navigation destinations; follows DEC-014/015 and preserves financial/session contracts. Verification tracked in task/evidence, not inferred from previews.

2026-11-17T13:24:15.294Z - [QA-030 presentation plan](fullscreen-forms-and-edge-sheets.md) / DEC-016: opaque full-screen forms, full-width compact choices and pinned Back. Shared presentation only; no new provider/model/router/schema contracts.
