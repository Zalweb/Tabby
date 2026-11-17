# settlement-and-receipts implementation plan

## Asynchronous mobile decision scope — 2026-11-13T18:07:00+08:00

Payment confirmation/rejection remains bound to its initiating session through local cache and alarm persistence. Its UI owns the exact modal route, so a late completion cannot dismiss a newer dialog. Financial detail/media/reminder/group sheets discard old-session content, including stacked receipt previews. Receipt panels and tab summaries support scrolling with large text while ledger records retain lazy paging. [QA-004](../progress/tasks/QA-004.md) records the reproductions, repairs and local evidence; native device/review gates remain open.

## Purpose and current state

Submission, confirmation, rejection, manual receipt recording and durable proof revisions. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Payments/backend agent**.

## Target behavior and contracts

Payments retain payer, recipient, payment ID, integer amount, method reference, status and proof references in SQL, cache and UI. Only recipient confirmation changes settled balances. Lock the pair before recomputing and confirming; reuse an operation ID safely. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [PAY-001](../progress/tasks/PAY-001.md) — Confirm Payment inserts a separate payment | P1 | Recipient confirms pending submission once; no additional payment row appears. |
| [PAY-002](../progress/tasks/PAY-002.md) — Submit Payment Proof does not attach payment proof | P1 | Payer submits proof offline/online and recipient sees it on the same payment. |
| [PAY-003](../progress/tasks/PAY-003.md) — Receipt status claims verification without evidence | P2 | Unverified files never receive a verified label; offline attachment survives process death and sync. |
| [PAY-004](../progress/tasks/PAY-004.md) — Concurrent confirmations may overpay | P1 | Concurrent confirmations whose sum exceeds debt cannot both succeed; exact debt never becomes overpaid. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Specific payment decisions and concurrent confirmation checkpoint 2026-10-31T18:09:20.800Z

Confirm/reject names the original payment UUID. Recipient alone can decide; confirmation/rejection preserves original payment rows and adds a private immutable audit. Confirming twice is safe; rejecting twice requires the same reason. The shared tab lock precedes balance validation and row mutation. Manual received-cash recording is distinct from wallet submission/confirmation.

See [verification](../verification/VER-PAY-001.md). No deployment; environment-specific limits remain open.

## Payment-bound durable proof and reference checkpoint 2026-10-31T18:25:52.891Z

submit_payment_v2 carries proof_path/reference in the same immutable money command and atomically binds metadata to the resulting payment. Subsequent payment proofs append using their own actor/operation UUID. Proof paths name uploaded private objects under the actor folder; recipient reads exact references. A file or reference never confirms money. Client queue captures pending image bytes before reporting a saved local payment.

See [verification](../verification/VER-PAY-002.md). No deployment; environment-specific limits remain open.

## Durable append-only receipt revisions checkpoint 2026-10-31T18:44:23.408Z

Expense attachments append transaction_receipt_revisions using append_transaction_receipt_v1 with actor/operation identity and exact own uploaded objects. Original transaction receipt fields are preserved; client transaction UPDATE/DELETE is revoked. Unified append_receipt operations retain upload bytes and target kind/ID; durable explicit ID mappings handle picker completion after financial synchronization. UI exposes current and prior receipts without claiming verification.

See [verification](../verification/VER-PAY-003.md). No deployment; environment-specific limits remain open.

## Immutable binary replay checkpoint — 2026-11-13T16:25:00+08:00

Proof/receipt upload retries must use create-only Storage requests. A duplicate path is acknowledged only after an authorized download matches the exact retained bytes in the initiating session. A different payload, unreadable object, unrelated upload failure or changed session cannot acknowledge the upload. This permits the durable money command to reach its idempotent RPC after a prior RPC commit made the object immutable and its response was lost. Empty/over-5-MB retained bytes fail before network use. Existing object protection and financial/receipt revision RPC contracts stay unchanged. [QA-003](../progress/tasks/QA-003.md) records the reproduced upsert defect, regression repair and remaining real Storage/device acceptance.


## App-wide warm presentation — 2026-11-17T08:16:51.570Z

The current user directive/DEC-014 extends welcome/introduction cream, amber and charcoal across this area's screens and overlays, with matching dark mode. [Current design authority](../project/DESIGN.md) and [QA-026](../progress/tasks/QA-026.md) supersede former mint/emerald presentation only. Existing behavior, financial meaning, native QR/image colors and session/durable-save guards remain. Verification must distinguish UI fixtures from actual provider/backend/device acceptance.
