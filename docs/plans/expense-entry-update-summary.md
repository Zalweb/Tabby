# Create Tab and custom amount update

## User-visible changes

Create Tab recognizes an existing registered shared tab by both user IDs. It offers **Add New Expense**, **View Existing Tab** and **Cancel**, with the outstanding PHP balance and who owes whom. Selecting, viewing or cancelling does not write an expense. Changing people inside an existing Add form also checks the newly selected person.

An expense with matching tab, amount, description, category, payer, allocations and recorded calendar date prompts **Possible Duplicate Expense**. **Review Existing Expense** is read-only; **Add Anyway** deliberately saves a separate transaction; **Cancel** keeps the draft. Equal amounts alone do not trigger the warning.

For the requested450 example: create a group with the two friends, enter450, enable **Custom amounts**, and enter **Your share0**, first friend150, second friend300. It records one group expense with those exact obligations. The existing per-person tabs are not charged again. Custom amounts also work within existing groups and bilateral/manual-contact tabs.

## Main files changed

- [Create/Add form](../../lib/features/tabs/presentation/add_expense_modal.dart): dialogs, review, exact existing-tab navigation, explicit group choice, custom inputs/drafts and confirmed/pending outcomes.
- [Expense policy](../../lib/features/tabs/domain/expense_entry_policy.dart) and [validation](../../lib/features/tabs/domain/ledger_validation.dart): contextual duplicate comparison and exact nonnegative centavo allocations, including zero shares.
- [Provider](../../lib/features/tabs/application/tabby_providers.dart) and [repository](../../lib/features/tabs/data/supabase_tabby_repository.dart): read-only pair lookup, exact tab/party separation, stable retry handling and correct zero-remaining wire allocations.
- Tests in `test/features/expense_entry_*`, `shared_tab_lookup_test.dart` and `expense_allocation_transport_test.dart`; Android form/storage fixtures and `scripts/usb-test*`; SQL/HTTP regressions in `scripts/test-money-commands.cjs` and `scripts/local-m1-http-regressions.mjs`.

## Duplicate and retry protection

Existing tabs retain their shared ID. Busy checks prevent repeated taps before async work. Attempted drafts retain the original operation and frozen command; server idempotency handles retries and response loss. Balances come from saved/reconciled ledger entries. A new save waits for authoritative history; failed network checks retain the draft. Backend sum/roster/authorization checks remain in place. No database migration or historical transaction/balance update was introduced.

## Verification and limits

Final frozen source passes903 tests, clean analysis,16 physical Android cases and39 isolated expense regressions. Twelve SDK transport cases cover either payer, registered users/manual contacts and viewer shares0/150/450. Native PostgreSQL and local PostgREST acceptance prove opposite account reads, one record after lost-response/parallel retries, a legitimate second150 loan reaching300, and0/150/300 custom balances.

Local signed test tokens are distinct from Google login or real two-device Realtime acceptance. Duplicate hints are contextual warnings rather than a guarantee that two independently created cross-device intents represent the same real-world bill. Advanced M2 tax/service features remain gated. Independent integration review and broader release gates remain open. See the [verification record](../verification/VER-QA-032-EXPENSE-ENTRY.md) for exact installed-version evidence and [results](../verification/QA-032-results.json).
