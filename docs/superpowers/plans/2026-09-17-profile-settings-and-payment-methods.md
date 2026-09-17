# Profile Settings and Payment Methods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`) syntax for tracking.

**Goal:** Implement the approved Profile experience in the production Flutter/Supabase app, including debtor-scoped QR payment methods, device security, Connections, preferences, sync diagnostics, and update status.

**Architecture:** Extend the current Riverpod providers and Supabase repository. Store payment methods in a private, RLS-protected collection with signed QR URLs; keep user preferences and security verifiers account-scoped in secure storage; expose app-wide theme, locale, and motion state from the root provider. Preserve the emerald Profile shell, existing Tabby ID flow, and PHP integer-centavo ledger.

**Tech Stack:** Flutter 3.24+, Dart 3.5+, Riverpod, Supabase/Postgres/RLS/Storage, local_auth, flutter_secure_storage, image_picker, connectivity_plus, crypto, http, package_info_plus, and Flutter widget/unit tests.

**Spec:** docs/superpowers/specs/2026-09-17-profile-settings-and-payment-methods-design.md

## Global Constraints

- Payment QR methods are visible only to a person who has an amount to pay the method owner inside the relevant shared tab.
- Each owner may have many active payment methods but at most one preferred/default method.
- PHP and USD are display preferences only; all ledger values remain PHP integer centavos.
- Native biometric/device authentication is used when available; biometric data never enters Tabby storage.
- The initial complete locale packs are English and Filipino.
- Notifications have one master on/off control.
- Appearance contains light/dark theme selection and motion on/off.
- Cached reads are available offline; QR uploads, expense creation, and payment confirmation require a live authenticated request.
- The existing emerald Profile outer layer, Tabby ID identity, account-scoped cache, Supabase RLS, and existing tests must remain intact.
- Do not stage or modify unrelated pre-existing worktree changes.

## File map

Create focused production units for payment methods, device authentication, preferences/localization, Connections, sync diagnostics, and About update state. Modify existing files only at the boundaries listed below.

- Create lib/features/payment_methods/domain/payment_method.dart for the payment-method value object and draft.
- Create lib/features/payment_methods/application/payment_methods_provider.dart for collection state and mutations.
- Create lib/features/payment_methods/presentation/payment_methods_sheet.dart for the production list/editor UI.
- Create lib/core/services/device_auth_service.dart for the injectable local-auth boundary.
- Create lib/core/services/pin_protection_service.dart for the salted PIN verifier.
- Create lib/core/localization/app_localizations.dart for the English/Filipino catalog and delegate.
- Create lib/features/profile/application/sync_diagnostics_provider.dart for connectivity and server-sync state.
- Create lib/features/connections/presentation/connections_screen.dart for the emerald Connections screen.
- Create supabase/migrations/20260917000005_payment_methods.sql for the table, RLS, storage, and debtor-scoped RPC.
- Create focused tests under test/features/.
- Modify models.dart, supabase_tabby_repository.dart, tabby_providers.dart, profile_screen.dart, tab_detail_screen.dart, biometric_gate.dart, app_router.dart, main.dart, tabby_theme.dart, app_update_models.dart, app_update_service.dart, schema_all.sql, pubspec.yaml, and pubspec.lock only as required below.
- Create test/support/profile_test_harness.dart with profileTestApp, preferredMethod, alternateMethod, and readUserSettings fixtures used by the widget snippets below.

---

### Task 1: Payment method domain model and secure Supabase boundary

**Files:**

- Create: lib/features/payment_methods/domain/payment_method.dart
- Create: supabase/migrations/20260917000005_payment_methods.sql
- Modify: lib/features/tabs/data/supabase_tabby_repository.dart
- Modify: supabase/schema_all.sql
- Test: test/features/payment_methods_data_test.dart

**Interfaces:**

- Add PaymentMethod with id, ownerUserId, provider, displayName, accountLabel, nullable qrStoragePath, nullable signed qrUrl, isActive, isDefault, and timestamps.
- Add PaymentMethodDraft with provider, displayName, accountLabel, nullable QR bytes, extension, and MIME type.
- Add repository methods:
  fetchPaymentMethods(String ownerUserId),
  createPaymentMethod({required String ownerUserId, required PaymentMethodDraft draft, required bool makeDefault}),
  updatePaymentMethod({required String methodId, required PaymentMethodDraft draft}),
  setPreferredPaymentMethod(String methodId),
  deletePaymentMethod(String methodId), and
  fetchPaymentMethodsForTab({required String tabId, required String payeeUserId}).

- [ ] **Step 1: Write failing tests** for map serialization, nullable QR data, legacy GCash/Maya/QR backfill, default-first sorting, malformed rows, and repository mapping.

~~~dart
test('round trips a payment method with a QR path', () {
  const method = PaymentMethod(
    id: 'method-1',
    ownerUserId: 'owner-1',
    provider: 'gcash',
    displayName: 'GCash QR',
    accountLabel: '09171234567',
    qrStoragePath: 'owner-1/method-1.png',
    isDefault: true,
  );

  expect(PaymentMethod.fromMap(method.toMap()), method);
});

test('legacy fields create one preferred method', () {
  final methods = PaymentMethod.fromLegacyUser({
    'id': 'owner-1',
    'gcash_number': '09171234567',
    'maya_number': '',
    'qr_code_url': 'legacy/owner-1.png',
  });

  expect(methods, hasLength(1));
  expect(methods.single.provider, 'gcash');
  expect(methods.single.isDefault, isTrue);
});
~~~

- [ ] **Step 2: Run the focused test and verify RED.**

Run: flutter test test/features/payment_methods_data_test.dart

Expected: FAIL because PaymentMethod and its legacy mapping do not exist.

- [ ] **Step 3: Implement the model and repository boundary.** Add strict fromMap/toMap conversion, fromLegacyUser, default-first sorting, UUID/path validation, storage upload through uploadBinary, private signed-URL creation, and safe failure returns. Do not expose another user's private fields through fetchUserProfile or friend discovery.

- [ ] **Step 4: Add the migration and schema parity.** Create the table, indexes, default uniqueness constraint, private bucket, owner policies, and list_payment_methods_for_tab(p_tab_id uuid, p_payee_user_id uuid) RPC. The RPC must verify authentication, bilateral tab membership, caller != payee, and get_net_balance(p_tab_id, auth.uid()) < 0 before returning the payee's active methods. Storage paths must be under the owner UUID. Backfill a method from non-empty legacy fields and keep legacy columns for compatibility.

~~~sql
CREATE TABLE IF NOT EXISTS public.payment_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  display_name TEXT NOT NULL,
  account_label TEXT NOT NULL DEFAULT '',
  qr_storage_path TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS payment_methods_one_default
  ON public.payment_methods(owner_user_id)
  WHERE is_active AND is_default;
~~~

- [ ] **Step 5: Run focused tests and static SQL checks.**

Run: flutter test test/features/payment_methods_data_test.dart

Expected: PASS. Verify the migration and schema_all.sql contain identical table/RLS/RPC definitions and no public bucket policy.

- [ ] **Step 6: Commit the vertical slice.**

~~~powershell
git add -- lib/features/payment_methods/domain/payment_method.dart lib/features/tabs/data/supabase_tabby_repository.dart supabase/migrations/20260917000005_payment_methods.sql supabase/schema_all.sql test/features/payment_methods_data_test.dart
git commit -m "feat: add private payment method data boundary"
~~~

### Task 2: Multiple QR/payment-method manager in Profile

**Files:**

- Create: lib/features/payment_methods/application/payment_methods_provider.dart
- Create: lib/features/payment_methods/presentation/payment_methods_sheet.dart
- Modify: lib/features/profile/presentation/profile_screen.dart
- Test: test/features/payment_methods_ui_test.dart

**Interfaces:**

- PaymentMethodsState exposes methods, isLoading, isSaving, and errorMessage.
- PaymentMethodsNotifier exposes load(), saveDraft(PaymentMethodDraft, {required bool makeDefault}), setPreferred(String methodId), and remove(String methodId).
- The sheet receives ownerUserId, reads paymentMethodsProvider, and uses ImagePicker only at the UI boundary. The repository receives bytes and validated metadata.

- [ ] **Step 1: Write failing production-widget tests.** Mount the real ProfileScreen with a provider override at the repository boundary. Assert tapping Payment Methods shows a list, Add Payment Method, Preferred labels, provider/account fields, and that choosing Preferred calls the notifier.

~~~dart
testWidgets('Profile opens the production payment-method manager', (tester) async {
  await tester.pumpWidget(profileTestApp(
    paymentMethods: const [preferredMethod, alternateMethod],
  ));
  await tester.tap(find.text('Payment Methods'));
  await tester.pumpAndSettle();

  expect(find.text('Preferred'), findsOneWidget);
  expect(find.text('Add Payment Method'), findsOneWidget);
  expect(find.text('GCash QR'), findsOneWidget);
  expect(find.text('Maya QR'), findsOneWidget);
});
~~~

- [ ] **Step 2: Run the focused widget test and verify RED.**

Run: flutter test test/features/payment_methods_ui_test.dart

Expected: FAIL because the current sheet is a single legacy QR editor.

- [ ] **Step 3: Implement the provider and sheet.** Replace the simulated URL flow with real ImagePicker.pickImage, file-size/MIME validation, progress/error states, list ordering, add/edit/delete, preferred selection, readable QR preview, and neutral empty state. Keep the existing legacy numbers visible as a migrated method or editable account label. Preserve emerald styling and modal scroll safety.

- [ ] **Step 4: Wire the Profile row to the provider.** The row subtitle shows the preferred provider and method count. The sheet is opened by the actual ProfileScreen row; no test-only navigation path is allowed.

- [ ] **Step 5: Run focused tests and analyzer.**

Run: flutter test test/features/payment_methods_ui_test.dart

Expected: PASS.

Run: flutter analyze lib/features/payment_methods lib/features/profile/presentation/profile_screen.dart

Expected: No issues found!

- [ ] **Step 6: Commit.**

~~~powershell
git add -- lib/features/payment_methods/application/payment_methods_provider.dart lib/features/payment_methods/presentation/payment_methods_sheet.dart lib/features/profile/presentation/profile_screen.dart test/features/payment_methods_ui_test.dart
git commit -m "feat: manage multiple profile payment methods"
~~~

### Task 3: Debtor-scoped payment QR selection in Tab Detail

**Files:**

- Modify: lib/features/tabs/presentation/tab_detail_screen.dart
- Modify: lib/features/payment_methods/application/payment_methods_provider.dart
- Modify: lib/features/tabs/data/supabase_tabby_repository.dart
- Test: test/features/payment_methods_payment_flow_test.dart

**Interfaces:**

- Add TabPaymentMethodRequest(tabId, payeeUserId) and tabPaymentMethodsProvider, a family provider that calls fetchPaymentMethodsForTab with both values.

- [ ] **Step 1: Write failing tests** for a debtor seeing the preferred method first, selecting an alternate method, and a user who does not owe the payee receiving an empty/unauthorized state. Assert the existing payment-proof action remains available when no QR is returned.

- [ ] **Step 2: Run the focused test and verify RED.**

Run: flutter test test/features/payment_methods_payment_flow_test.dart

Expected: FAIL because Tab Detail renders the simulated QR preview and reads legacy counterpart fields directly.

- [ ] **Step 3: Implement the authorized fetch and selection UI.** Replace direct private-field reads with the tab-scoped provider. Render the preferred method as the first QR card, show provider/account label, and expose a compact selector for alternates. Use signed URLs only after repository authorization succeeds. Keep QR preview, copy/save actions, and payment-proof flow functional.

- [ ] **Step 4: Run focused payment-flow tests.**

Run: flutter test test/features/payment_methods_payment_flow_test.dart

Expected: PASS, including no private method data shown for an unrelated user.

- [ ] **Step 5: Commit.**

~~~powershell
git add -- lib/features/tabs/presentation/tab_detail_screen.dart lib/features/payment_methods/application/payment_methods_provider.dart lib/features/tabs/data/supabase_tabby_repository.dart test/features/payment_methods_payment_flow_test.dart
git commit -m "feat: show debtor-scoped payment QR choices"
~~~

### Task 4: Device authentication and Tabby PIN

**Files:**

- Create: lib/core/services/device_auth_service.dart
- Create: lib/core/services/pin_protection_service.dart
- Modify: lib/features/tabs/application/tabby_providers.dart
- Modify: lib/features/profile/presentation/profile_screen.dart
- Modify: lib/core/widgets/biometric_gate.dart
- Modify: pubspec.yaml and pubspec.lock to add crypto for salted PIN hashing
- Test: test/features/security_settings_test.dart

**Interfaces:**

~~~dart
abstract interface class DeviceAuthService {
  Future<bool> isSupported();
  Future<List<BiometricType>> availableBiometrics();
  Future<bool> authenticate({
    required String reason,
    bool allowDeviceCredential = true,
  });
}

abstract interface class PinProtectionService {
  Future<bool> hasPin(String userId);
  Future<void> setPin(String userId, String pin);
  Future<bool> verifyPin(String userId, String pin);
  Future<void> clearPin(String userId);
}
~~~

- [ ] **Step 1: Write failing tests** for capability labels, biometric enable requiring a successful challenge, PIN set/verify/change, scoped secure-storage keys, cancellation preserving disabled state, and auto-lock selecting the configured method.

~~~dart
test('cancelled biometric challenge does not enable security', () async {
  final notifier = UserSettingsNotifier(
    auth: FakeDeviceAuthService(supported: true, result: false),
    pinProtection: FakePinProtectionService(),
  );

  expect(await notifier.enableBiometric(), isFalse);
  expect(notifier.state.securityMethod, SecurityMethod.none);
});
~~~

- [ ] **Step 2: Run the focused test and verify RED.**

Run: flutter test test/features/security_settings_test.dart

Expected: FAIL because current settings store independent booleans and have no PIN service/capability abstraction.

- [ ] **Step 3: Implement injectable device auth and PIN protection.** Wrap local_auth, use getAvailableBiometrics, permit OS device credentials when selected, hash a random-salt PIN verifier with crypto, and scope every key by authenticated user ID. Extend UserSettings with a SecurityMethod enum, motionEnabled, themeMode, currencyCode, and languageCode while preserving compatibility with stored booleans.

- [ ] **Step 4: Update Security UI and lock gate.** Show only available methods with names such as Fingerprint or Face ID, add Configure PIN/Change PIN, and preserve auto-lock. BiometricGate keeps the app locked after cancellation and retries through the configured service; unavailable hardware is never shown as active.

- [ ] **Step 5: Run focused security tests and analyzer.**

Run: flutter test test/features/security_settings_test.dart

Expected: PASS.

Run: flutter analyze lib/core/services lib/core/widgets/biometric_gate.dart lib/features/tabs/application/tabby_providers.dart

Expected: No issues found!

- [ ] **Step 6: Commit.**

~~~powershell
git add -- lib/core/services/device_auth_service.dart lib/core/services/pin_protection_service.dart lib/core/widgets/biometric_gate.dart lib/features/tabs/application/tabby_providers.dart lib/features/profile/presentation/profile_screen.dart pubspec.yaml pubspec.lock test/features/security_settings_test.dart
git commit -m "feat: add configurable device security"
~~~

### Task 5: Preferences, theme, motion, and English/Filipino localization

**Files:**

- Create: lib/core/localization/app_localizations.dart
- Modify: lib/features/tabs/application/tabby_providers.dart
- Modify: lib/main.dart
- Modify: lib/core/theme/tabby_theme.dart
- Modify: lib/features/profile/presentation/profile_screen.dart
- Modify: lib/features/navigation/presentation/main_scaffold.dart
- Test: test/features/profile_preferences_test.dart

**Interfaces:**

- UserSettings exposes currencyCode (PHP/USD), notificationsEnabled, motionEnabled, themeMode (light/dark), and languageCode (en/fil).
- AppLocalizations.of(context) returns the catalog for the current locale. supportedLocales is [Locale('en'), Locale('fil')].
- TabbyApp watches userSettingsProvider and supplies theme, darkTheme, themeMode, locale, and MediaQueryData.disableAnimations from actual root state.

- [ ] **Step 1: Write failing widget tests** that tap Currency, Notifications, Appearance, and Language in the real Profile tab; assert persisted state changes root theme/locale/motion; assert PHP/USD does not modify ledger centavos; assert English/Filipino strings change in Profile and Connections.

~~~dart
testWidgets('currency preference changes display without changing centavos', (tester) async {
  await tester.pumpWidget(profileTestApp());
  await tester.tap(find.text('Currency'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('US Dollar (USD)'));
  await tester.pumpAndSettle();

  expect(readUserSettings().currencyCode, 'USD');
  expect(sampleLedgerEntry.amountCentavos, 12500);
});
~~~

- [ ] **Step 2: Run the focused test and verify RED.**

Run: flutter test test/features/profile_preferences_test.dart

Expected: FAIL because only Light mode and English are currently available and the root app does not consume Profile preferences.

- [ ] **Step 3: Implement settings persistence and root wiring.** Scope secure-storage preference keys by authenticated user, connect notification master to the existing notification service, add TabbyTheme.darkTheme, and apply motion state to custom mascot/page animation settings. Currency remains formatter-only.

- [ ] **Step 4: Implement the localization delegate and catalogs.** Move strings used by Profile, Connections, payment/security sheets, sync diagnostics, About update status, and bottom navigation into English and Filipino key getters. Set MaterialApp.router locale and supported locales from the provider.

- [ ] **Step 5: Run focused preferences tests and analyzer.**

Run: flutter test test/features/profile_preferences_test.dart

Expected: PASS.

Run: flutter analyze lib/core/localization lib/core/theme lib/main.dart lib/features/profile lib/features/navigation

Expected: No issues found!

- [ ] **Step 6: Commit.**

~~~powershell
git add -- lib/core/localization/app_localizations.dart lib/core/theme/tabby_theme.dart lib/main.dart lib/features/navigation/presentation/main_scaffold.dart lib/features/profile/presentation/profile_screen.dart lib/features/tabs/application/tabby_providers.dart test/features/profile_preferences_test.dart
git commit -m "feat: add profile preferences and localization"
~~~

### Task 6: Emerald Connections screen and route

**Files:**

- Create: lib/features/connections/presentation/connections_screen.dart
- Modify: lib/core/router/app_router.dart
- Modify: lib/features/profile/presentation/profile_screen.dart
- Test: test/features/connections_screen_test.dart

**Interfaces:**

- Add /connections as an authenticated root route. ProfileScreen navigates with context.push('/connections').
- ConnectionsScreen consumes existing friendsProvider and tabbyProvider.friendRequests; it invokes existing sendFriendRequestByCode, respondToFriendRequest, and removeFriend operations.

- [ ] **Step 1: Write failing widget tests** for the emerald header, curved canvas, Friends/Requests segmented control, search, friend rows, request actions, and Add Friend Tabby ID flow.

- [ ] **Step 2: Run the focused test and verify RED.**

Run: flutter test test/features/connections_screen_test.dart

Expected: FAIL because /connections and the full-screen Connections widget do not exist.

- [ ] **Step 3: Implement the screen and route.** Reuse existing responsive Wrap behavior for narrow headers, keep the emerald outer layer, and preserve current friend-code/RLS actions. Do not duplicate friend identity or create a second contact-tab path.

- [ ] **Step 4: Run focused test and commit.**

Run: flutter test test/features/connections_screen_test.dart

Expected: PASS.

~~~powershell
git add -- lib/features/connections/presentation/connections_screen.dart lib/core/router/app_router.dart lib/features/profile/presentation/profile_screen.dart test/features/connections_screen_test.dart
git commit -m "feat: add emerald connections screen"
~~~

### Task 7: Honest Sync & Offline diagnostics

**Files:**

- Create: lib/features/profile/application/sync_diagnostics_provider.dart
- Modify: lib/features/tabs/application/tabby_providers.dart
- Modify: lib/features/tabs/data/tabby_local_cache.dart only for persisted sync metadata
- Modify: lib/features/profile/presentation/profile_screen.dart
- Test: test/features/sync_diagnostics_test.dart

**Interfaces:**

~~~dart
enum SyncStatus { ready, syncing, offline, needsAttention }

class SyncDiagnosticsState {
  const SyncDiagnosticsState({
    required this.status,
    this.lastSuccessfulSync,
    this.cachedTabsCount = 0,
    this.cachedActivitiesCount = 0,
    this.cachedRemindersCount = 0,
    this.errorMessage,
  });

  final SyncStatus status;
  final DateTime? lastSuccessfulSync;
  final int cachedTabsCount;
  final int cachedActivitiesCount;
  final int cachedRemindersCount;
  final String? errorMessage;
}
~~~

- [ ] **Step 1: Write failing tests** for offline/online transitions, cached counts, last-success updates only after a successful refresh, manual retry, and no false synchronized message after a failed request.

- [ ] **Step 2: Run focused test and verify RED.**

Run: flutter test test/features/sync_diagnostics_test.dart

Expected: FAIL because the current sheet hardcodes Supabase/Drift statuses and treats a started refresh as successful.

- [ ] **Step 3: Implement the provider.** Listen to connectivity_plus, call the existing TabbyNotifier.refreshTabs() through an injected callback, record lastSuccessfulSync only after a successful live fetch, read account-scoped cache counts, and persist diagnostic metadata in secure storage. Make refreshTabs() return Future<bool> so diagnostics can distinguish success from a swallowed error.

- [ ] **Step 4: Replace the Profile sheet.** Show Online/Offline, Ready/Syncing/Needs attention, cached counts, last sync time, stale-data note, and Sync now/retry. Keep preferences available offline; explain payment/expense writes require a connection.

- [ ] **Step 5: Run focused tests and commit.**

Run: flutter test test/features/sync_diagnostics_test.dart

Expected: PASS.

~~~powershell
git add -- lib/features/profile/application/sync_diagnostics_provider.dart lib/features/tabs/application/tabby_providers.dart lib/features/tabs/data/tabby_local_cache.dart lib/features/profile/presentation/profile_screen.dart test/features/sync_diagnostics_test.dart
git commit -m "feat: add honest sync diagnostics"
~~~

### Task 8: About Tabby update status

**Files:**

- Modify: lib/features/app_update/domain/app_update_models.dart
- Modify: lib/features/app_update/data/app_update_service.dart
- Modify: lib/features/profile/presentation/profile_screen.dart
- Test: test/features/about_tabby_update_test.dart

**Interfaces:**

~~~dart
enum AppUpdateStatus { checking, upToDate, updateAvailable, unavailable }

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    required this.installedVersion,
    this.release,
  });

  final AppUpdateStatus status;
  final AppVersion installedVersion;
  final AppUpdateRelease? release;
}

abstract interface class AppUpdateStatusChecker {
  Future<AppUpdateCheckResult> checkStatus();
}
~~~

- [ ] **Step 1: Write failing tests** for manual About check states: loading, up to date, newer release with notes/link, and network/API failure. Confirm the automatic AppUpdatePrompt remains non-blocking.

- [ ] **Step 2: Run focused test and verify RED.**

Run: flutter test test/features/about_tabby_update_test.dart

Expected: FAIL because AppUpdateService.checkForUpdate() returns null for both up-to-date and failure, and Profile uses a hardcoded version dialog.

- [ ] **Step 3: Implement status-aware checking.** Add checkStatus() without breaking the existing AppUpdateChecker used by AppUpdatePrompt, return explicit failure/up-to-date states, and update About to show installed version, latest version, notes, retry, and platform release URL.

- [ ] **Step 4: Run focused tests and commit.**

Run: flutter test test/features/about_tabby_update_test.dart

Expected: PASS.

~~~powershell
git add -- lib/features/app_update/domain/app_update_models.dart lib/features/app_update/data/app_update_service.dart lib/features/profile/presentation/profile_screen.dart test/features/about_tabby_update_test.dart
git commit -m "feat: show explicit app update status"
~~~

### Task 9: Full production integration verification

**Files:**

- Modify only the production/test files already listed when a verification failure requires a correction.
- Test: existing full suite plus all new feature tests.

- [ ] **Step 1: Add or update production integration assertions.** Verify the real TabbyApp root consumes theme/locale/motion providers, /connections is guarded by the authenticated router, Profile uses the multiple-method manager, and Tab Detail uses debtor-scoped payment methods.

- [ ] **Step 2: Run the complete test suite.**

Run: flutter test

Expected: all existing tests and all new tests PASS.

- [ ] **Step 3: Run static analysis and formatting checks.**

Run: flutter analyze

Expected: No issues found!

Run: dart format --output=none lib test

Expected: no formatting failures.

Run: git diff --check

Expected: no whitespace errors. Review git status --short and confirm unrelated pre-existing changes are not staged.

- [ ] **Step 4: Verify the final production path.** Launch the app or run the relevant integration/widget entry point, open Profile, add a real QR method through the Supabase-backed repository, set a preferred method, open a debtor tab, verify preferred/alternate selection, open Security/Connections/Sync/About, and confirm each state is rendered by the main app route.

## Execution order

Execute Tasks 1 through 8 in order because later UI slices consume earlier data and provider contracts. Run Task 9 after every slice is green. Apply the Supabase migration to the linked project only after migration static review and Flutter repository contract tests pass; report the migration result separately from local test results.
