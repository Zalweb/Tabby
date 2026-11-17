# Create Tab and custom debt design

User supplied the implementation specification and requested immediate implementation using relevant frontend/backend skills. Native execution is retained in the current session. This document records the requested design and routine implementation decisions; it does not authorize unrelated rollout, live-data migration or release.

## Goals and constraints

- Selecting a registered person in a one-to-one Create Tab flow performs an immutable-ID pair lookup, independent of creator/direction. No financial write occurs on selection, review, view or cancellation.
- Existing dialog title: **You already have a tab with [Username]**. Body: **You already have a shared tab with this person. Would you like to add a new expense or view your existing transactions?** Show the actual outstanding PHP amount and viewer-relative debt direction. Actions: **Add New Expense**, **View Existing Tab**, **Cancel**.
- Add goes to the existing Add to Tab form using its actual tab ID; View opens that tab's ledger. Cancel leaves selection and ledger unchanged. New relationships continue Create Tab. A failed live lookup is retryable and must not be misrepresented as no relationship.
- A possible duplicate is an expense in the same tab with the same centavo amount, normalized description, expense category/type, payer, allocation and recorded local calendar date. Payments, cancelled/reversal records and the current operation's own retry are excluded. Amount alone is insufficient. This is a warning, not a uniqueness rule across legitimate separate expenses.
- Duplicate title: **Possible Duplicate Expense**. Body: **A similar expense has already been recorded in this tab. Are you sure this is a new transaction?** Actions: **Review Existing Expense**, **Add Anyway**, **Cancel**. Review shows the candidate's existing record without writing. Add Anyway authorizes only this unchanged form fingerprint. Cancel keeps the draft. Every subsequent edit invalidates that authorization.
- Custom amounts are a normal integrated split choice in Create/Add, with one money input per actual party, including the payer. Zero shares are allowed. Inputs must be nonnegative integer centavos after parsing and sum exactly to the entered total. Example450: payer0, friend150, friend300. Same-name people remain separate identities. For a group, use only active registered accepted members; an existing manual contact remains a supported bilateral party.
- Existing repayment direction, append-only corrections/history, group party accounting and QR/manual-confirmation contracts are unchanged. No synthetic records in the everyday account.

## Approaches and decision

Reuse the current form, canonical pair model, provider's serialized durable save/replay and already-supported explicit participant allocation RPC. This avoids parallel writers or a second ledger. Existing CustomSplit/centavo validation can supply the simple zero-charge math. New taxes/service charges, recurrence, claiming and advanced review are not requested and their M2 flags remain unchanged. Verify the existing M1 RPC accepts and independently validates the150/300/0 allocation before choosing this path; do not bypass a missing server contract or mark the broader CAP-002 tax/service rollout complete. If a required contract is missing, prepare a narrowly scoped additive repair and evidence before any live application.

Do not replace the financial store, deduplicate by names/amounts, silently merge historical tabs, or enforce an irreversible same-amount uniqueness rule. A parallel custom-split writer would duplicate retry/session logic; silently using the existing tab without the requested dialog would retain the confusing behavior.

## Interaction and interfaces

The Add People step keeps group creation explicit so selecting an existing friend for a new group does not redirect into their unrelated bilateral tab. Existing-group selection stays group-scoped. One-person selection invokes `SharedTabLookup` under captured actor/session and a latest-selection token; stale results cannot open another account's dialog. Remote membership/identity remains authoritative. Cache-only fixtures/offline drafts are distinguished from confirmed live reads.

`AddExpenseModal(initialCounterpartId: actualTabId)` is the existing Add to Tab route; label it Add to Tab and seed the exact participant roster without the creation dialog. New drafts say Create Tab. Reuse full-screen form navigation, guarded Back, TabbyFeedback and warm palette; use scrollable branded dialogs with accessible actions and amount+direction text. Review can open a read-only expense detail built from the matched record. Preserve draft contents unless the user explicitly submits or discards them.

`ExpenseDuplicatePolicy` is pure and testable; `ExpenseDraftFingerprint` contains tab ID, normalized details, date, payer and explicit shares. Approval never generates a different operation ID. After an ambiguous send, freeze the original command; repeated taps and retry use it. Persist before network. Show a confirmed success only for an acknowledged result; show an explicit pending/attention state otherwise. Balance state is derived from actual ledger records and safely reconciled; no standalone balance increment.

## Verification and limits

Cover all ten user scenarios: no tab; existing tab; opposite account; legitimate equal-amount second loan; duplicate warning/review; cancel; repeated Save; response loss/retry; both registered readers; confirmed balance150→300. Add zero payer150/300, exact cents, negative/under/over allocation, changed draft after override, different payer/category/description/date, payments/reversals, stale session/selection, existing manual contact and new/existing groups.

Use unit/widget regressions, real native PostgreSQL/API authorization/concurrency acceptance and physical Android fixtures. Clearly distinguish injected UI/SQL-role/signed test-token fixtures from real Google authentication or actual Realtime delivery. Preserve private credentials and all original ledger fingerprints in any authorized remote fixture test. Current normal18 and the spare test app stay intact until a checked higher-version private upgrade; no public release is included.

Builder-check resolution: a fresh expense cannot save when authoritative history refresh fails; show retryable feedback and keep the draft. An already-attempted frozen operation may retry unchanged with its original ID, even while history is unavailable. This preserves response-loss recovery without silently skipping new-expense checks.
