# missing-capabilities implementation plan

## Purpose and current state

Complete agreed MVP capabilities after core contracts stabilize. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Feature agent**.

## Target behavior and contracts

M2 features remain hidden/unadvertised until acceptance passes. Audit-preserving correction/cancellation is M1. Claiming contacts requires explicit consent; recurrence occurrences have unique stable identities. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [CAP-001](../progress/tasks/CAP-001.md) — Documented ledger capabilities are absent | P2 | Every missing capability maps to a task and hidden/available behavior matches its verified status. |
| [CAP-002](../progress/tasks/CAP-002.md) — Custom splits and tax/service charges | P2 | Custom allocations sum exactly, including odd cents, zero shares and validation failures. |
| [CAP-003](../progress/tasks/CAP-003.md) — Recurring obligations | P2 | Replay generates one occurrence; timezones, month-end, pause/resume and offline reconciliation pass. |
| [CAP-004](../progress/tasks/CAP-004.md) — Explicit contact claiming | P2 | Decline makes no change; accepted claim preserves entries and retries are idempotent. |
| [CAP-005](../progress/tasks/CAP-005.md) — Acknowledgment, proposals and disputes | P2 | Unauthorized users cannot accept; concurrent decisions resolve once; rejected proposals never change balances. |
| [CAP-006](../progress/tasks/CAP-006.md) — Audited corrections and cancellation | P2 | Wrong expense can be corrected without deletion; each party sees the revision and balances replay exactly. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## CAP-001 exposure correction 2026-11-01T18:50:46.205Z

Current entry supports equal splits and payer-excluded/full-share allocations, not arbitrary individual amounts. Group shares remain group-specific obligations. Both landing mirrors now describe that behavior. Expense badges say Recorded without claiming explicit counterpart consent; serialized historical statuses are unchanged. No acknowledgment, proposal, dispute, recurrence or claiming action is introduced. CAP-002 through CAP-005 own those M2 flows; CAP-006 remains M1 per master plan and metadata despite its seeded M2 body heading. Corrections/cancellation is not available yet. [Evidence](../verification/VER-CAP-001.md).

## CAP-006 initial shared contract 2026-11-01T18:57:30.348Z

request_expense_change_v1(operation_id, transaction_id, kind, new_total, reason) freezes an actor-scoped request; identical operation/payload replays, changed payload conflicts. Only the two registered participants of a normal individual-tab expense can request/review; groups, contacts, historical malformed rosters and generated reversal rows fail closed. decide_expense_change_v1(change_id, accept) accepts only the other participant. No balance changes before acceptance. Acceptance locks the original expense, appends a reverse-direction expense for the old debtor share and a replacement with the original payer/split proportion (integer truncation, payer receives centavo remainder). A unique accepted-result row per source expense prevents competing proposals applying twice. Cancellation appends only reversal. Original entries and payments remain immutable; list_expense_changes_v1 exposes reason, status and output references to the actual parties. Pending/rejected/stale proposals never affect balance. Client waits for acknowledgment and refreshes normal history, so existing arithmetic replays the appended entries. Group/contact corrections remain unfinished and must not be exposed.

## CAP-006 bilateral implementation checkpoint 2026-11-01T19:17:52.918Z

The previously frozen request and decision RPCs additionally require p_expected_actor; the server compares it with the JWT subject before writing, preventing an old form from acting as a later account. Request payloads persist before networking and cannot be replaced during uncertain acknowledgment. Source amount corrections preserve the original payer and allocation proportion with integer debtor-share truncation and payer remainder. A confirmed payment remains after cancellation; any resulting reverse balance is a real retained obligation. Valid registered two-person tabs have an actual detail-sheet action; group/contact and generated-reversal requests fail closed. Counterpart notifications and immutable request/decision/result/audit rows are present. Task stays in_progress for group/contact, offline audit/reminder projection, SDK/device and environment acceptance; it is not a release gate closure. [Evidence](../verification/VER-CAP-006-BILATERAL.md).

## CAP-006 completed source contract 2026-11-01T19:49:19.092Z

request_expense_change_v2 adds explicit manual-contact outside-app agreement while v1 remains compatible for registered parties. Registered group changes require all other frozen registered participants, not a single reviewer. Self-only group expenses need no other reviewer. Claimed contacts cannot use manual attestation. Per-output audit covers every compensating reversal and replacement. Approved metadata is explicitly selected through an authorized computed field and serialized in the existing cache; originals/reversals remain financial history but do not become duplicate reminder candidates. Pending original reminder/queued push jobs retire at application. DEC-009 records the consent distinction. Earlier group/contact/offline limitations are superseded by this implementation; deployment/device gates remain open. [Evidence](../verification/VER-CAP-006-SOURCE.md).

## M2 contract freeze � 2026-11-02

Integration owner: Codex root on `codex/m1-application-fixes`. Hidden M2 development is explicitly authorized while M1 real-environment dependencies remain open. No dependency or release gate is waived. Application constants and server `m2_feature_flags` default false; no environment/experimental UI switch enables them. Fixture tests may enable disposable-database flags only.

CAP-002 uses explicit PartyRef base shares. Tax and service rates are integer basis points in 0..10000 and apply independently to the base, with half-up centavo rounding. Each charge is distributed proportionally by largest remainder, with kind/immutable-ID ties; zero shares stay zero. Server independently recomputes totals and persists the breakdown alongside normal immutable participants. M2 writes join the existing account-scoped replay owner and actor/operation registry; same ID/different payload conflicts, and saved uncertain requests remain frozen.

CAP-003 rule anchors and IANA timezones are immutable; edit changes future templates/frequency/end bounds through expected-revision checks. Calendar dates are derived from the original anchor, preserving month-end intent rather than chaining clamped dates. Pause/end never remove occurrences. Activation/resume excludes older missed dates; offline replay and scheduler materialization identify one occurrence by rule/calendar date. Service materialization must validate the current owner/roster and create audited financial records without impersonating user JWTs. Existing occurrences replay without mutation.

CAP-004 invites an explicitly selected registered account, not a name/phone match. Decline makes no financial/identity change. Acceptance locks and checks a frozen source-ledger snapshot, retains original contact/financial references, appends net-balance compensating/transfer entries, links consent and archives the old contact relationship. Existing registered-pair history remains separate and unchanged, with the new transfer appended. Stale/ambiguous sources need a fresh invitation; old queued writes cannot add new obligations to the archived/claimed relationship.

CAP-005 acknowledgment is a separate immutable attestation, never inferred from historical transaction status. Existing recorded balances remain until an approved append-only adjustment. Amount proposals reuse frozen participant approval from CAP-006; rejection leaves balances unchanged. Disputes retain originals and balances, and an agreed resolution is recorded with all required registered parties' consent; a financial resolution uses the approved correction workflow. No unregistered contact is represented as an authenticated reviewer. M2 UI/marketing remains hidden until actual acceptance and dependency evidence passes.

## M2 source checkpoint and rollout recovery ? 2026-11-02

[Custom splits](../verification/VER-CAP-002-IMPLEMENTATION.md), [recurrence](../verification/VER-CAP-003-IMPLEMENTATION.md), [contact claiming](../verification/VER-CAP-004-IMPLEMENTATION.md), and [expense review](../verification/VER-CAP-005-SOURCE.md) now have source implementations and local regressions. They remain hidden. Source success does not satisfy real Supabase, device, review or dependency acceptance.

Expense acknowledgments are immutable per transaction/registered actor and exclude creator self-acknowledgment. Existing transaction status and participant acknowledged flags do not establish this attestation. Proposals use the existing CAP-006 unanimous registered-reviewer contract through a deterministic inner operation, with an outer M2 operation preserving exact payload replay/conflict. Rejected proposals create no compensating financial rows. Disputes use separate tables: they never set the historical balance-exclusion transaction status. Resolution text is frozen, its proposer votes explicitly, and every frozen registered party must agree. Rejection leaves the dispute open; another resolution may be proposed. Resolution does not perform an amount adjustment. Unregistered-contact consent remains the CAP-006 explicit outside-app agreement path; M2 does not invent an authenticated contact reviewer. Current review summaries expose the latest 50 proposals and open/recent 50 disputes, with pending resolutions retained in each bounded summary; older audit rows remain stored. Broader audit-history pagination remains an improvement before exposure if acceptance requires it.

Rollout rollback: keep all four application constants false and database flags false until acceptance. After an enabled staging trial, disabling a database flag blocks new operations but still returns a matching existing actor/operation result; changed intent conflicts and inactive accounts remain denied. Retain additive RPCs/tables and existing financial/audit rows. Do not drop data, downgrade migrations or rewrite claims/occurrences to roll back UI exposure. A forward repair must reconcile recorded operation/output IDs and append approved financial corrections. Source tests cover disabled-new versus recorded-replay behavior; actual deployment/upgrade/rollback remains unverified.


## Requested update: custom debts with a zero-share payer — 2026-11-17T13:46:55.658Z

Tracked under [CAP-002](../progress/tasks/CAP-002.md). Support both money lent and purchases paid for others: one PHP450 entry allocated PHP150 to User1, PHP300 to User2 and PHP0 to the payer. Preview who owes whom and require allocations to equal the total exactly. Use clear borrower/lender and Add entry versus Create tab wording. New entries for the same registered person accumulate in the canonical running tab; users should reuse existing manual-contact identities. Never double-count a group obligation by copying it into a personal ledger. Include repayment isolation, idempotent retry and duplicate-charge warnings in acceptance. This update is planned for user exposure; existing hidden custom-split code and disabled rollout flags are unchanged.


## Plain custom amounts delivered in private Android20 — 2026-11-17T18:55:00.494Z

The requested plain unequal/custom amount entry is implemented in the normal Create/Add form and privately installed in Android1.0.4+20: payer0, first person150, second300 for a450 total. Existing groups and explicit new groups are supported, as are bilateral contact custom shares. CAP-002 advanced tax/service form and other M2 flags remain unchanged; this does not claim the broader advanced rollout or production approval. Existing shared-tab confirmation and duplicate Review/Add Anyway/Cancel are part of QA-032. See [QA-032](../progress/tasks/QA-032.md) for evidence and remaining limits.
