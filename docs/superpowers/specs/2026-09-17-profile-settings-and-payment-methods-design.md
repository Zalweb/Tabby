# Profile Settings, Payment Methods, and Connections Design

**Date:** 2026-09-17  
**Status:** Approved for implementation  
**Scope:** Profile tab and the payment/security/preferences flows reached from it

## Goal

Extend the existing Profile tab without changing its emerald outer layer. The Profile tab becomes the control center for payment QR methods, device security, connections, display preferences, offline diagnostics, and update status. The implementation must use the production Flutter/Riverpod/Supabase app wiring and must not introduce a test-only screen or fake persistence.

## Product decisions

- Payment QR methods are private payment instructions. A person can see them only when they have an amount to pay the method owner inside a shared tab. They are not exposed from Profile, Friends, friend discovery, or a general public user lookup.
- Each user can save multiple payment methods and mark exactly one as the preferred/default method. The debtor sees the preferred method first and can select another method.
- The first currency choices are Philippine Peso (PHP) and US Dollar (USD). This is display-only. The ledger continues to store and calculate PHP integer centavos; no exchange-rate conversion is introduced.
- Security uses native device authentication when available: fingerprint, Face ID, or another OS-provided biometric. A device passcode may be used through the native authentication prompt. A separate Tabby PIN is available as an app-local fallback/choice and is never stored in plain text.
- The initial complete language pack is English and Filipino. The language architecture uses locale keys so more languages can be added without rewriting screen logic.
- Notifications have a single master on/off control in Profile.
- Appearance includes a light/dark theme choice and a motion on/off preference. The emerald Profile shell is preserved in both themes.
- Offline mode provides cached reads and honest synchronization diagnostics. Authoritative financial writes remain online-only in this phase to prevent duplicated or falsely confirmed ledger entries.

## User experience

### Profile

Keep the existing emerald outer header and curved mint canvas. Keep the compact identity block and grouped sections:

- Account: Payment Methods, Security, Manage Friends.
- Preferences: Currency, Notifications, Appearance, Language.
- Data & Support: Sync & Offline, Help Center, About Tabby.
- Full-width outlined Log Out action.

The Payment Methods row shows the preferred provider and the number of saved methods. Security shows the selected method and availability state. Currency, appearance, language, and notification subtitles reflect the persisted settings. Manage Friends opens the Connections screen.

### Payment methods

The Payment Methods sheet is a list manager, not a single QR editor. It supports:

1. Add a method with a provider/name, optional account identifier or note, and optional QR image.
2. Pick a QR image from the device, validate supported image type/size, upload it to private Supabase Storage, and show an upload/error state.
3. Set one method as Preferred. The preferred method is clearly labeled and pinned first.
4. Edit, remove, or replace a method. Removing the preferred method promotes the next active method, or leaves the collection without a preferred method if empty.
5. Preview each QR at a readable size.

Suggested providers include GCash, Maya, Bank Transfer, PayPal, and Other, while allowing a custom display name so a user can add any personal payment QR. Account identifiers are displayed only to authorized debtors and the owner.

When a debtor opens the payment action in a tab, the payment sheet requests the payee's eligible methods. It displays the preferred method first, followed by a method selector. If the user has no eligible QR method or the network is unavailable, the sheet explains that the payee has not added a payment QR and keeps the existing payment-proof flow available.

### Security

The Security sheet detects capabilities through `local_auth` and lists only usable options. The user can enable biometric/device authentication, configure a Tabby PIN, and control auto-lock. Enabling a method requires a successful confirmation. PIN creation requires confirmation and stores a salted verifier in scoped secure storage. The app never receives or stores biometric templates.

The app lock gate uses the selected method on resume. Authentication failures keep the app protected and provide retry/fallback actions; an unavailable hardware method is not presented as enabled.

### Connections

Manage Friends opens a production `/connections` route with the same emerald header treatment and curved canvas language as Profile. The screen contains a Friends/Requests segmented control, search, connected friend rows, request actions, and an Add Friend action using the existing Tabby ID flow. Existing friend-code identity, connected-account handling, and RLS boundaries remain unchanged.

### Preferences

- Currency: PHP or USD display selection only; existing currency formatter remains PHP-authoritative for ledger calculations.
- Notifications: one master switch. Existing notification scheduling is canceled or allowed according to this master preference.
- Appearance: light/dark theme selection and motion switch. Motion off disables app-level/custom motion while retaining functional transitions.
- Language: English and Filipino options, persisted per account. User-visible strings in Profile, Connections, payment/security sheets, sync diagnostics, update status, and navigation labels come from the localization catalog.

### Sync & Offline

The diagnostics sheet presents:

- Current connectivity and the result of the last real server request.
- Last successful synchronization time.
- Whether cached tabs, activities, and reminders are available and their counts.
- Current sync state: Ready, Syncing, Offline, or Needs attention.
- A Sync now action and a retry message for failed refreshes.

Existing account-scoped secure cache remains the first read source. A real server refresh updates the timestamp only after success. Connectivity alone does not claim that data is synchronized; a server request confirms it. Cached financial data is clearly labeled as possibly stale. Profile preference changes can be saved locally, while QR uploads, expense creation, and payment confirmation require a live authenticated server request.

### About Tabby

About shows the installed version and a stateful manual update check:

- Checking for updates.
- Up to date, including the installed version.
- Update available, including the latest version, notes, and a platform-appropriate release link.
- Unable to check, with a retry action.

The existing automatic update prompt continues to use the same GitHub release source. A null result from a failed request must not be presented as “up to date.”

## Data model and access control

Add a `public.payment_methods` table with:

- `id`, `owner_user_id`, `provider`, `display_name`, `account_label`, `qr_storage_path`.
- `is_active`, `is_default`, `created_at`, and `updated_at`.

Add a partial unique index or transaction-safe function so each owner has at most one default active method. Keep the existing legacy `users.gcash_number`, `users.maya_number`, and `users.qr_code_url` columns during migration. Backfill a legacy row into `payment_methods` where data exists, then use the collection for new reads and writes.

Create a private `payment-methods` storage bucket with image MIME and size limits. Owner policies allow insert/update/delete only within the owner's path. Debtor access is mediated by a narrowly scoped authenticated function or equivalent RLS policy that verifies the caller has a positive obligation to the owner in the requested tab. The function returns only the fields needed for payment selection and the storage path; it must not broaden access to unrelated users or pending friend lookups. Signed URLs are generated only after that authorization succeeds.

Payment-method reads and updates are exposed through repository methods and a Riverpod provider. The tab payment UI never queries the `users` table directly for another user's private payment fields.

## Application architecture

- Add payment-method domain models, repository methods, provider state, cache-safe serialization, and Supabase migration/schema parity.
- Extend the scoped user settings model with currency, notifications, motion, theme, language, security method, and PIN metadata. Keep secrets in `flutter_secure_storage` with user-scoped keys.
- Add an injectable native-auth capability service so widget tests can cover biometric availability, PIN setup, failure, and fallback without requiring hardware.
- Add an app-preferences provider consumed by `TabbyApp` so theme, locale, and motion settings affect the actual root `MaterialApp`, not only a Profile preview.
- Add a sync diagnostics provider that listens to connectivity changes, records the result of real refreshes, and exposes state to the Profile sheet.
- Extend the update domain from a nullable update-only result to a state that distinguishes up-to-date, available, checking, and unavailable/error.
- Add the Connections route while retaining the existing bottom navigation shell and current friend providers.

## Error handling and safety

- QR uploads show progress, reject unsupported files, and leave the existing method unchanged on failure.
- A failed default change, delete, or update is reported and does not optimistically claim success.
- Payment-method authorization failures return no private rows and show a neutral unavailable state.
- Device-auth cancellation never enables a security method. PIN verification is rate-limited within the app session and has a recovery path through the authenticated account/device credentials.
- Offline cache data is always scoped to the current authenticated user. Logout clears the active user's cache and local security state according to existing logout behavior.
- Update-check failures remain non-blocking and are retryable from About.

## Testing and acceptance criteria

Tests are written before implementation for each production behavior and then run against the real widgets/providers/routes:

- Payment-method model serialization, migration/backfill behavior, default uniqueness, upload validation, add/edit/delete/default flows, and debtor-only visibility.
- Tab payment UI shows the preferred QR first and allows selecting alternatives; an unrelated user cannot retrieve methods.
- Security capability detection, biometric enable/disable, PIN setup/verify/change, auto-lock, and failure/fallback behavior.
- Connections route, emerald header, Friends/Requests switching, search, and existing Tabby ID actions.
- PHP/USD display preference without changing integer-centavo ledger values; notification, motion, theme, and English/Filipino persistence.
- Sync status transitions, cached read labels, last-success timestamp, manual retry, offline behavior, and logout scoping.
- About states for checking, up to date, update available, and failed checks.
- Full `flutter test`, `flutter analyze`, and `git diff --check` verification. No production code is hidden behind test-only mocks; test doubles are injected only at service boundaries.

## Non-goals for this implementation

- No currency conversion or exchange-rate service.
- No public directory of QR codes.
- No custom facial-recognition engine.
- No background financial write queue or automatic settlement confirmation while offline.
- No claim that connectivity by itself proves synchronization.
- No removal of existing Tabby ID/RLS behavior.
