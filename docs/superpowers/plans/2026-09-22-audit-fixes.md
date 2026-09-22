# Plan: Post-Audit Fixes & Verification (2026-09-22)

> **Status: COMPLETE (2026-09-22).** All five tasks implemented and verified:
> `flutter analyze` 0 issues, `flutter test` 182/182 passing, `node test/web_landing_test.js` 100%,
> release APK rebuild successful. Dedup guard was tightened further than planned: semantic merging now
> only bridges a local temp ID with a server ID (two server entries never merge, and two local
> *financial* activities never merge), while the local 30-second nudge anti-spam merge is preserved.

Source: comprehensive audit findings. Repo: C:\Users\frien\Documents\Rizal_V1 MVP\Tabby (branch main).

## Task 1 — Tighten ledger & activity deduplication (prevent eating legitimate entries)
- `lib/features/tabs/data/mock_tabby_repository.dart` `deduplicateLedgerEntries`:
  semantic merge rules (amount+isPayment+title/category+time window) may ONLY merge when at least
  one side has a temporary local ID (starts with `entry-`, `payment-`, or is not a server UUID).
  Two server-UUID entries with different IDs must NEVER be merged. Exact-ID match stays.
- `lib/features/tabs/application/tabby_providers.dart` `deduplicateActivities`:
  same guard — two server-UUID activities with different IDs must never merge; `_normalizeActivityTitle`
  containment match only applies when at least one side has a temp ID (`act-`/`entry-`/`payment-`).
- Add regression tests: two legitimate same-amount same-category expenses 10 min apart with different
  titles and server UUIDs must both survive; temp+server pair must merge.

## Task 2 — Real receipt attachment via image_picker
- `lib/features/tabs/presentation/tab_detail_screen.dart`: replace fake
  `receipt_<ts>.png` success path with `ImagePicker` gallery/camera chooser; upload bytes to
  Supabase `payment-proofs` bucket when online (`SupabaseConfig.paymentProofsBucket`), store the
  returned path/URL via `attachReceiptToEntry`; show error SnackBar on failure instead of fake success.
- Keep graceful offline behavior: store local file path as receiptUrl and queue/sync note.
- Update/extend widget tests for the new flow.

## Task 3 — Remove dead code and unused dependencies
- Delete unused RPC helpers in `lib/core/config/supabase_config.dart`: `getTabSummary`,
  `getUserDashboardSummary`, `claimContact` and constants `rpcGetTabSummary`,
  `rpcGetUserDashboardSummary`, `rpcClaimContact`.
- Delete unused `MockTabbyRepository.sampleFriends`.
- Remove unused pubspec deps: `rive`, `lottie`, `drift`, `sqlite3_flutter_libs`, `path_provider`,
  `riverpod_annotation`, `drift_dev`, `riverpod_generator` (verify no imports first; keep
  `image_picker`, `flutter_image_compress` only if used by Task 2).
- Run `flutter pub get` and confirm `flutter analyze` stays clean.

## Task 4 — Website fallback refresh to v1.0.3
- `docs/index.html`, `docs/app.js`, `landing/index.html`, `landing/app.js` (+styles if needed):
  update hardcoded fallback version/size/date to v1.0.3 / 74.8 MB (78444824 bytes) / September 19, 2026.
- Keep docs/ and landing/ 100% mirrored; `node test/web_landing_test.js` must pass.

## Task 5 — Full verification pass
- `flutter analyze` (0 issues), `flutter test` (all pass), `node test/web_landing_test.js`.
- Add/extend tests covering: no duplicate tabs on addExpense twice, no duplicate ledger entries on
  pull-to-refresh reload, add-expense flow end-to-end per page (Home FAB, My Tabs, Tab Detail,
  Connections), settle flow accuracy (net balance math), notification dedup.
- Report: analyze count, test counts, any remaining failures.
