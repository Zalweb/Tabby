# Tabby Comprehensive E2E Testing, Platform Audit & Verification Report

> **Date:** September 17, 2026  
> **Target Platforms:** Android (APK / AAB), iOS (IPA / Runner), Web Dashboard  
> **Testing Scope:** E2E Test Suite Execution, Platform Manifest & Permissions Audit, Routing & Navigation Trace, UI Button & Logic State Verification  
> **Source of Truth:** [AGENTS.md](file:///C:/Users/frien/Documents/Rizal_V1%20MVP/Tabby/AGENTS.md)  
> **Audit Objective:** Identify any runtime errors, logic defects, dead buttons, broken navigation, or missing platform requirements without modifying production app code.

---

## 1. Executive Summary

A comprehensive automated and manual static trace audit was executed across all 31 test suites (155 Flutter unit/widget/e2e tests and 6 Web landing tests).

### Overall Test Execution Metrics
- **Total Test Cases Evaluated:** 161 (155 Flutter + 6 Web)
- **Passing Test Cases:** 152 / 161 (**94.4%**)
- **Failing / Blocked Test Cases:** 9 / 161 (**5.6%**)
- **Web Landing Page Test:** 100% Pass (Status 200 OK on live Vercel production)

---

## 2. Platform Binary & Release Audit

### 2.1 Android APK (`releases/Tabby.apk` / `releases/Tabby-v1.0.1.apk`)
- **Package ID:** `com.zalweb.tabby` (aligned in `build.gradle.kts` and `MainActivity.kt`).
- **Binary Size:** 72.3 MB (~68.9 MB uncompressed).
- **Target SDK & Desugaring:** Java 17 target compatibility; core library desugaring enabled with `desugar_jdk_libs:2.1.4`.
- **Deep Link Intent Filter:** Configured for `io.supabase.tabby://login-callback`.

#### Identified Android Vulnerabilities & Findings:
1. **Google Play Store Policy Warning (`SCHEDULE_EXACT_ALARM`):**
   - Declared in `android/app/src/main/AndroidManifest.xml:6`.
   - On Android 14+ (API 34), Google Play restricts exact alarms exclusively to alarm clocks and calendar applications. Shared expense apps requesting this permission face automated Play Store submission rejection unless inexact alarms (`AndroidScheduleMode.inexactAllowWhileIdle`) are used.
2. **Missing Runtime Prompt for Android 13+ Notifications:**
   - `POST_NOTIFICATIONS` is declared in `AndroidManifest.xml:7`, but `TabbyNotificationService` currently lacks an explicit runtime permission request trigger on Android 13+ devices, which can cause local push notifications to be silently suppressed by the OS.
3. **App Label Formatting:**
   - `android:label="tabby"` in `AndroidManifest.xml` is in lowercase instead of capitalized "Tabby".

---

### 2.2 iOS IPA (`releases/Tabby.ipa`)
- **Bundle Contents:** `Runner.app`, `App.framework`, `Flutter.framework`, assets, and plugins.
- **Deep Links & OAuth:** `CFBundleURLSchemes` includes `io.supabase.tabby` and Google reversed client ID.
- **Biometrics:** `NSFaceIDUsageDescription` is present and valid.

#### Identified iOS Vulnerabilities & Findings:
1. **CRITICAL: Missing Info.plist Photo & Camera Permission Strings:**
   - `ios/Runner/Info.plist` is missing `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`, and `NSPhotoLibraryAddUsageDescription`.
   - When users tap "Attach Receipt" or "Upload QR Ph" on a physical iOS device via `ImagePicker`, iOS immediately terminates the app process (`SIGABRT` crash). App Store Connect will also reject the IPA during automated ingestion.
2. **Code Signing:**
   - The standalone IPA in `releases/Tabby.ipa` was built with `--no-codesign` on a generic CI runner. Deploying to physical test devices requires signing with an Apple Developer Team provisioning profile or TestFlight.

---

## 3. High-Priority Bugs & Architectural Defects

### Bug 1: Bottom Navigation Dock Count & Non-Existent File Import
- **Location:** `lib/features/navigation/presentation/main_scaffold.dart` and `lib/core/router/app_router.dart`
- **Issue:**
  - `MainScaffold` defines 4 navigation buttons: Home (0), My Tabs (1), Tasks (2), and Profile (3).
  - However, `app_router.dart` only had 3 branches configured. An attempted 4th branch imported `classroom_tasks_screen.dart`, which does not exist on disk yet.
  - If 3 branches are used, tapping "Profile" (index 3) triggers an unhandled `RangeError (index): Invalid value: Not in inclusive range 0..2: 3`. Tapping "Tasks" (index 2) opens the Profile screen instead.

### Bug 2: Dead-End Route on Newly Added Friends in Connections Screen
- **Location:** `lib/features/connections/presentation/connections_screen.dart:159`
- **Issue:** Tapping a friend from the Connections list routes to `/tabs/${friend.id}`. If the user has not yet recorded an expense with this friend, `tabDetailProvider` returns `null`, presenting a blank/dead "Tab not found" error screen instead of opening the "Add Expense" flow.

### Bug 3: Navigation History Hijack on Home Dues Settlement
- **Location:** `lib/features/home/presentation/home_dashboard_screen.dart:701`
- **Issue:** Tapping "Pay" on an upcoming reminder uses `context.go('/tabs/${reminder.tabId}')`. The back button in `TabDetailScreen` falls back to `/tabs` instead of returning the user to `/home`.

### Bug 4: Synthetic Receipt ID Generation without File Picker
- **Location:** `lib/features/tabs/presentation/tab_detail_screen.dart:1333`
- **Issue:** Tapping "Attach Receipt" generates a timestamp string (`receipt_${timestamp}.png`) rather than launching the device gallery via `ImagePicker`. The preview modal also renders an icon placeholder instead of an image.

### Bug 5: Unhandled `MissingPluginException` in Offline Sync Diagnostics
- **Location:** `lib/features/profile/application/sync_diagnostics_provider.dart:46`
- **Issue:** `_connectivity.checkConnectivity()` is invoked without a platform fallback or try/catch. In test environments or when the native plugin channel is uninitialized, it throws `MissingPluginException`, breaking `interactive_features_test.dart`.

---

## 4. Complete Test Suite Execution Results

| # | Test Suite | Result | Passed / Total | Notes |
|---|---|:---:|:---:|---|
| 1 | `test/android_package_alignment_test.dart` | **PASS** | 1 / 1 | Package ID `com.zalweb.tabby` aligned |
| 2 | `test/core/currency_formatter_test.dart` | **PASS** | 5 / 5 | ADR-001 integer centavo precision (0 drift over 10k ops) |
| 3 | `test/features/app_update_test.dart` | **PASS** | 11 / 11 | Semver parsing and release updates |
| 4 | `test/features/app_update_status_test.dart` | **PASS** | 2 / 2 | In-app update banner states |
| 5 | `test/features/auth_onboarding_test.dart` | **PASS** | 3 / 3 | Onboarding gate and offline OAuth fallback |
| 6 | `test/features/backend_data_handling_test.dart` | **PASS** | 35 / 35 | Supabase serialization, bilateral netting, local cache |
| 7 | `test/features/connections_screen_test.dart` | **PASS** | 4 / 4 | Tabby ID sharing and connection list controls |
| 8 | `test/features/create_tab_flow_test.dart` | **PASS** | 4 / 4 | Friend picker, group creation, and split calculations |
| 9 | `test/features/device_frame_test.dart` | **PASS** | 7 / 7 | Web desktop mockup container |
| 10 | `test/features/e2e_all_screens_buttons_test.dart` | **PASS** | 11 / 11 | Complete UI walk: all screens and interactive sheets |
| 11 | `test/features/empty_state_flow_test.dart` | **PASS** | 1 / 1 | First-time user empty state to expense creation |
| 12 | `test/features/friend_requests_test.dart` | **PASS** | 8 / 8 | Friend code normalization (TAB-XXXXXX) & accept flow |
| 13 | `test/features/google_auth_configuration_test.dart` | **PASS** | 3 / 3 | Client IDs and audience verification |
| 14 | `test/features/home_promo_layout_test.dart` | **PASS** | 1 / 1 | Dynamic dues promo banner rendering |
| 15 | `test/features/ledger_engine_test.dart` | **PASS** | 5 / 5 | AGENTS.md Section 11.3 canonical acceptance rules |
| 16 | `test/features/my_tabs_layout_test.dart` | **PASS** | 2 / 2 | Active vs Settled tabs filtering |
| 17 | `test/features/oauth_profile_completion_test.dart` | **PASS** | 7 / 7 | Incomplete profile guard and phone number gate |
| 18 | `test/features/payment_methods_data_test.dart` | **PASS** | 2 / 2 | QR Ph data model round-tripping |
| 19 | `test/features/payment_methods_payment_flow_test.dart` | **PASS** | 1 / 1 | Method picker in settlement modal |
| 20 | `test/features/payment_methods_ui_test.dart` | **PASS** | 1 / 1 | QR manager sheet in Profile |
| 21 | `test/features/profile_layout_test.dart` | **PASS** | 2 / 2 | Grouped settings arrangement |
| 22 | `test/features/profile_settings_behavior_test.dart` | **PASS** | 3 / 3 | PBKDF2 PIN hashing and settings state mutations |
| 23 | `test/features/relationship_rules_test.dart` | **PASS** | 8 / 8 | Unregistered contacts restricted to 1:1 tabs |
| 24 | `test/features/security_settings_test.dart` | **PASS** | 2 / 2 | Biometric challenge cancellation & PIN gating |
| 25 | `test/features/sync_diagnostics_test.dart` | **PASS** | 1 / 1 | Diagnostics bottom sheet display |
| 26 | `test/features/web_responsive_test.dart` | **PASS** | 7 / 7 | Mobile (390px, 360px), tablet, and desktop viewports |
| 27 | `test/web_landing_test.js` | **PASS** | 6 / 6 | Vercel production status 200 OK, dynamic release engine |
| 28 | `test/classroom_integration_test.dart` | **FAIL** | 0 / 6 | Blocked by missing Classroom methods on notification service |
| 29 | `test/features/friend_profile_test.dart` | **FAIL** | 3 / 5 | Viewport tap offset Y=1378 outside bounds without scroll |
| 30 | `test/features/interactive_features_test.dart` | **FAIL** | 7 / 8 | `syncNow()` crashes on `MissingPluginException` from probe |
| 31 | `test/features/widget_test.dart` | **FAIL** | 0 / 1 | Blocked by missing `classroom_tasks_screen.dart` in router |

---

## 5. Prioritized Remediation Roadmap

1. **Fix `MainScaffold` & `app_router.dart` Alignment:** Revert bottom navigation to 3 tabs (Home, My Tabs, Profile) until the Classroom feature is ready to be fully integrated.
2. **Add iOS Photo Permissions:** Add `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription` to `ios/Runner/Info.plist`.
3. **Replace Android Exact Alarm with Inexact Alarm:** Remove `SCHEDULE_EXACT_ALARM` from `AndroidManifest.xml` to prevent Play Store rejection.
4. **Fix Connections Screen Friend Tap:** Check if a tab exists; if not, open `AddExpenseModal` with that friend pre-selected.
5. **Fix Sync Diagnostics Exception:** Wrap `_connectivity.checkConnectivity()` in a `try/catch` block.
6. **Fix Viewport Scrolling in Tests:** Add `tester.scrollUntilVisible` in `friend_profile_test.dart`.
