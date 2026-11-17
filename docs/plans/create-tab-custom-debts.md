# Create Tab and Custom Debts Implementation Plan

> For agentic workers: implement this plan natively in the current session, following the user's explicit implementation request and recorded repository ownership. Use the relevant execution/debugging/design skills and a fresh builder/review check; do not spawn implementation agents without applicable authorization.

**Goal:** Recognize existing relationships before entry, prevent accidental duplicate expense saves, and let a payer allocate450 as0/150/300 while preserving existing sync/history.

**Architecture:** Extend the existing Create/Add form with a pure identity/duplicate policy and reusable custom amount inputs. Use the existing canonical tab and explicit-participant/durable RPC contract; retain all unrelated M2 rollout gates. Confirmation/candidate review is read-only, and successful financial state must come from acknowledged or safely reconciled ledger records.

**Tech stack:** Flutter/Riverpod/GoRouter, existing native storage/draft/replay, Supabase/PostgREST/PostgreSQL and Android verification tools; no new dependencies or schema by default.

**Spec:** [Approved user scope and design](create-tab-custom-debts-design.md). Owner: [QA-032](../progress/tasks/QA-032.md).

## Global constraints

Integer centavos; immutable party IDs; canonical one-to-one relationship; append-only confirmed history; manual payment confirmation; session-scoped async results; preserve registered/group/manual-contact functionality and QA-030 full-screen presentation. No automatic financial writes during selection/dialog/review. Use exact user-supplied dialog copy/actions. Do not count matching amounts alone as proof of a duplicate.

## Review focus

- A friend may already have the canonical tab before any expense; distinguish an existing empty ledger from no relationship.
- Group selection must not be intercepted by a member's unrelated bilateral tab.
- A lost response followed by draft restoration must reuse the same command, not warn about or submit its own saved transaction again.
- Another device can add an entry after the initial local lookup; refresh authoritative history before a new submit when online and retain server idempotency.
- A zero-share payer and a contact payer must retain explicit actual parties; cancelled/reversal/payment rows must not become duplicate expense candidates.

## Task 1 — Policies and canonical lookup

Files: new `lib/features/tabs/domain/expense_entry_policy.dart`; narrow `lib/features/tabs/data/supabase_tabby_repository.dart` lookup; new `test/features/expense_entry_policy_test.dart` and lookup transport cases.

- [x] Add failing identity, opposite-account, empty-tab, description/date/type/allocation duplicate tests, with0/150/300 integer fixtures.
- [x] Add typed read-only pair lookup using captured actor and stable user IDs; failed network read is not no tab. Return exact tab identity/balance/roster, or an explicit unavailable result for a non-writable existing tab.
- [x] Implement pure candidate/fingerprint/allocation validation. Run focused tests red then green; preserve unrelated repository auth changes.

## Task 2 — Existing-tab dialog and correct Create/Add navigation

Files: `add_expense_modal.dart`, narrow tab-detail/history routing helper if needed, reusable confirmation UI; existing/new create-flow widget tests.

- [x] Add failing tests for the three actions and no-write selection/cancel/view, current debt direction, stale async lookup and group/contact preservation.
- [x] Integrate explicit one-person/group intent, latest-selection/session fence and exact requested dialog. Add starts the existing tab form; View opens its ledger; Cancel leaves financial state unchanged. Label Create/Add/View distinctly and preserve current full-screen/draft/Back behavior.
- [x] Add fresh history duplicate warning with Review Existing Expense/Add Anyway/Cancel; authorize one unchanged draft only, retain stable operation ID. Test legitimate equal amounts, rejected/cancelled/payment candidates and editing after override.

## Task 3 — Integrated custom amounts and durable save truth

Files: `add_expense_modal.dart`, new `custom_amount_fields.dart` if useful, narrow optional explicit allocation input in `tabby_providers.dart`/`ledger_validation.dart`, existing custom-split calculator reuse and tests.

- [x] Write failing Create/Add0/150/300, under/over/negative/odd-cent tests and payer/member identity cases.
- [x] Reuse existing M1 explicit participant allocation contract after actual backend proof. Do not enable unrelated advanced M2 features. Add custom choice/preview to Create and Add and persist all amounts in the existing encrypted scoped draft.
- [x] Keep save disabled while busy; freeze ambiguous commands and duplicate override; expose acknowledged/pending/attention outcomes honestly. Retain shared ledger-derived accounting and serialized queue/replay. Test rapid taps, retry and unchanged opposite-party debt/confirmed repayment behavior.

## Task 4 — Backend and two-account acceptance

Files: focused tests in `scripts/`, Android case contract/fixture under `integration_test/`, narrow SQL repair only if a real missing contract is reproduced.

- [x] Prove0/150/300 through existing RPC, exact cents/roster enforcement, canonical pair from either actor, read authorization for both accounts, one transaction under repeated/parallel same operation, payload conflict denial and new operation same amount allowed.
- [x] Exercise response loss/retry, exact final balances and both account readers through real API/SDK ports. Keep Auth provenance explicit and test unrelated users denied. No original financial rows may change in remote tests.
- [x] Run actual Android Create/Add/dialog/custom input fixtures and applicable notification/navigation neighbors. Never replace the signed user app with a credential-bearing test fixture.

## Task 5 — Integration, review and delivery

- [x] Run scoped then full Flutter/analysis, relevant backend/native suites and memory refresh/plain/base checks; inspect failures rather than loosening assertions.
- [x] Review the final code/requirements and source hashes; preserve concurrent work in owned commits/snapshots. Record actual pending/unverified environments and original attempt failures.
- [x] Build/verify a higher signed normal Android version with public config only, preserve the existing tablet session/data and confirm exact installed bytes if current authorization and release checks permit private delivery. Record no-public-release limits.
- [x] Update QA-032/CAP-002 plans and verification evidence; summarize changed files, UI/logic/idempotency measures, results and remaining limitations.

2026-11-18T03:24:00+08:00 - Implementation checklist is satisfied for the primary delivered20 flow; final22 composition includes the additional person-switch and zero-remaining wire fixes. Full903, clean analysis, native16 and focused39 pass; signed22 packaging remains running. Checklist verification is scoped to recorded local/Android evidence, with independent review and real two-device Realtime still unverified. Later22 installed-byte evidence supersedes packaging-pending status only when explicitly recorded.


2026-11-17T19:31:49.240Z — All requested expense updates plus the two review follow-ups are privately installed in normal22, with903/16 verification and exact installed bytes. [Final results](../verification/QA-032-results.json). Broad release/independent review and real two-device Realtime limits remain explicit.
