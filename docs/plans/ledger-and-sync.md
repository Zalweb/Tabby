# ledger-and-sync implementation plan

## Same-session read ordering — 2026-11-13T18:07:00+08:00

Session generation alone cannot order two reads in the same session. Ledger refreshes now carry a monotonic read revision; a newer refresh, reset or acknowledged payment decision invalidates older snapshots. Obsolete refreshes do not publish balances/status, continue later cache/alarm writes or report synchronization success. Default repository/RPC contracts are unchanged. Delayed-read regressions and remaining device/platform limits are recorded in [QA-004 evidence](../verification/VER-QA-004-MOBILE.md).

## Purpose and current state

Identity reconciliation, durable writes, session isolation, bounded retries and accurate synchronization. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Data/sync agent**.

## Target behavior and contracts

Expense and payment commands retain a stable operation ID across retries. One queue owns execution. Server uniqueness is scoped to actor and operation ID; a changed payload under the same ID is rejected. Permanent failures enter needsAttention; transient failures use capped exponential backoff. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [LED-001](../progress/tasks/LED-001.md) — Different people merge by display name | P1 | Two registered Alex accounts and two same-name groups remain separate after refresh and restart. |
| [LED-002](../progress/tasks/LED-002.md) — Distinct same-price expenses disappear | P1 | Lunch and Coffee at the same price ten minutes apart both survive local/server refresh. |
| [LED-003](../progress/tasks/LED-003.md) — Retries can duplicate server writes | P1 | Drop the response after commit and retry concurrently; exactly one expense/payment exists. |
| [LED-004](../progress/tasks/LED-004.md) — Failed operations can continuously retry | P1 | Permanent failures become needsAttention; retry count does not grow while idle; transient retries are delayed. |
| [LED-005](../progress/tasks/LED-005.md) — Contact payer and settlement paths lose synchronization | P1 | A contact can pay or owe; expenses and partial cash settlements persist through refresh/restart. |
| [LED-006](../progress/tasks/LED-006.md) — Sync diagnostics overstate success | P2 | Server errors with connectivity available show failure, retain cache and never report synchronized. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## INT-001 contract freeze, 2026-10-31

Integration owner: Codex root, codex/m1-application-fixes. Reservations: shared models/providers, schema and command contracts require integration-owner review before edits.
PartyRef wire shape is {kind: user|contact, id: immutable string}; groups are containers, never parties. Temporary identities require explicit mappings, never name matching. Expense commands contain operation_id, tab_id, payer PartyRef, total_centavos, shares [{party, amount_centavos}], occurred_at and attachment_refs. Payment commands retain submission_id, operation_id, payer, recipient, amount_centavos, method_id, provider, status, timestamps and proof revisions. Proof references contain object_path and pending_upload; signed URLs are disposable views. Sync states are queued, syncing, synced, retryableFailure and needsAttention. Results carry account_id and session_generation and are discarded when either changes.
Reserved versioned RPC names: create_expense_v1, submit_payment_v1, confirm_payment_v1, reject_payment_v1 and record_received_payment_v1. These are target contracts, not deployed functions. Actor/operation uniqueness returns the original result for identical payloads and conflicts for changed payloads. Confirmation serializes pair balance checks. Legacy reads remain compatible; unsupported financial writes must fail explicitly. Existing implementations require adapter/migration review before replacement.
Contract review: checked against master-plan invariants; executable identity fixtures now prohibit name reconciliation. Remaining contract fixtures (retry conflicts, payment lifecycle, session isolation) are still required before INT-001 acceptance and dependent financial implementation.

### 2026-10-31 contract review superseding the partial freeze

Integration owner reviewed the complete target against DEC-003/004/005/007.
[Command fixtures](../../test/fixtures/m1_commands.json) specify actor-scoped replay/conflict, recipient-only confirmation, immutable proof history and same-account re-login generation rejection. These are normative behavioral inputs/expected outputs for dependent acceptance suites; they do not establish deployed server behavior. [Executable fixtures](../../test/features/shared_contract_test.dart) exercise durable queue identity/account separation and pending-versus-confirmed balance effects. Session generation discard, conflict rejection and recipient authorization still require implementation/integration evidence in SEC-004, LED-003 and PAY-001.

Versioned financial RPCs accept `p_operation_id: UUID` and a command payload; stable IDs are generated once before enqueue. The payload must include all financial fields; the server compares canonical JSONB under an actor/operation lock. A replay returns the original result only for an equal payload; a changed command returns a conflict without changing history. Operation identities must be stored explicitly with transaction IDs rather than inferred from UUID-looking local entry IDs. Payment submission and confirmation have distinct operation IDs and share the original submission ID. Confirmation/rejection operate on that submission, never insert another payment. Proof revisions contain immutable object references; replacing a proof appends a revision.

The integration owner serializes shared repository/provider/model, routing, dependency, schema and workflow edits. In this session that owner is Codex root; no parallel agent claims exist. Compatibility adapters may retain legacy read shapes. Legacy writes must be removed or explicitly rejected as their versioned replacements land, with upgrade tests before deployment. No versioned RPC is claimed deployed by this freeze.

### 2026-10-31 retry implementation checkpoint

LED-004 now stores attempt_count, sync_state and next_attempt_at in the account-scoped durable queue. Transient/unknown failures wait 5/10/20/40 seconds between externally triggered attempts and stop at five attempts in needsAttention; unsupported operation types stop immediately. Sync's final refresh does not start another replay, and the executor acquires its guard before awaiting connectivity. Typed authorization/validation failures, manual retry UI and server acceptance remain open. These local controls do not supply LED-003 server idempotency.

### 2026-10-31 versioned operation implementation checkpoint

LED-003 adds an actor/operation registry, advisory transaction lock and canonical JSONB conflict check. Registered-party expense/payment commands use create_expense_v1/submit_payment_v1; their p_command compatibility payload currently retains the former p_* allocation fields. This adapter is intentionally narrower than the final PartyRef command: contact payer/manual receipt support and the full occurred_at/proof lifecycle remain in LED-005/PAY tasks. It does not establish completion of those contracts.

The client freezes the exact RPC payload in the durable queue before sending it. Immediate writes now request the same replay executor. On success, explicit local_entry_id-to-result mapping is saved before queue acknowledgement; no name, amount or UUID-prefix inference is used. Legacy queue items without a safe mapping enter needsAttention, preserving them for reconciliation rather than replaying a possibly already committed write. Legacy RPC execution and direct financial INSERT privileges are revoked; deploy only after reviewing the installed client inventory and staging upgrade tests. No migration is deployed here.

Permanent typed authorization/validation/constraint failures and unsupported intents enter needsAttention immediately. Unknown/transient failures retain capped backoff. Local PostgreSQL/WASM acceptance uses real allocation/payment functions, while staging and independent database-session concurrency remain unverified. Run the pinned optional local harness with the instructions in [verification protocol](../verification/README.md).

### 2026-10-31 contact parties and local-tab identity

Contacts now resolve by explicit owner-scoped identity, never by name. New contacts use UUIDs; legacy temporary IDs map deterministically within an account. A local tab carries isLocalOnly rather than relying on UUID appearance. Contact expenses use typed participant allocations atomically. record_received_payment_v1 records explicit cash received/paid in the owner's private contact ledger, retaining actual payer/recipient PartyRefs separately from recorder/confirmation actor. This is an owner-attested personal cash record; no unregistered-wallet verification is asserted. Contact non-cash proof flows remain excluded. The server bounds and locks these records and retains actor-scoped operation conflicts. Local SQL/client tests pass; staging and device acceptance remain open.

### 2026-10-31 sync diagnostics checkpoint

SyncReport distinguishes a successful server read from local saves and includes pending/attention counts. A network probe cannot mark synchronized. The diagnostics sheet displays counts, last successful sync and explicit saved-write retry. Retrying preserves operation identity/payload; unmapped legacy records remain held. Failed ledger/balance reads retain cache and cannot masquerade as a successful empty response. Queue read failures are strict on mutation/sync, preventing corruption from being overwritten as an empty queue. Real outage/device acceptance remains unverified.

## Exact activity identity reconciliation checkpoint 2026-10-31T19:45:57.560Z

Activity identity follows the financial operation journal. Equal content is never enough to merge IDs. A durable local-entry-to-server-entry result mapping may reconcile that exact activity ID; server rows win repeated IDs. Mapping/activity-cache checkpoints precede queue acknowledgment. Legacy logs lacking mappings remain distinct; pending payment activity never claims confirmation.

See [verification](../verification/VER-LED-002.md). No deployment; environment-specific limits remain open.


## Expense entry compatibility contract — 2026-11-17T18:55:00.494Z

TabbyNotifier.addExpense accepts optional customAmounts keyed by actual party IDs. The provider validates exact roster/sum, prefers an exact chosen tab ID over counterpart matches and separates tab identity from payer/counterpart identity. Stable queued operation IDs survive draft restore and ambiguous response retries. Bilateral acknowledged retries compare the existing summary allocation rather than treating hydrated participant-list representation as a changed intent; groups retain full roster comparison. A new save requires successful authoritative history refresh; an already attempted frozen operation retries unchanged. No historical SQL update or schema migration is introduced. See [QA-032](../progress/tasks/QA-032.md) for evidence and remaining limits.
