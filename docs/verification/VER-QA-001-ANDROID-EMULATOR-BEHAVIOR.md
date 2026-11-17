# VER-QA-001-ANDROID-EMULATOR-BEHAVIOR ? API 37 emulator behavioral acceptance

```json verification-metadata
{
  "id": "VER-QA-001-ANDROID-EMULATOR-BEHAVIOR",
  "tasks": [
    "QA-001",
    "AND-001",
    "AND-002",
    "AND-003",
    "AND-004"
  ],
  "tested_commit": "0c07362c43bc6430e727662ab4d5fa35fc47402a",
  "tested_tree": "dirty; integration harness and dependency changes were present",
  "platform": "Windows; Android emulator Medium_Phone_API_37.0; emulator-5554; API 37; x86_64",
  "environment": "emulator acceptance with Flutter integration_test and adb; synthetic data only; no Auth-issued identity",
  "commands": [
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_acceptance_test.dart -d emulator-5554 --keep-app-running",
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_draft_restart_test.dart -d emulator-5554 --keep-app-running",
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_inexact_fallback_test.dart -d emulator-5554 --keep-app-running",
    "adb shell dumpsys alarm",
    "adb shell dumpsys notification --noredact",
    "adb shell bmgr backupnow com.zalweb.tabby",
    "adb reboot"
  ],
  "result": "partial_pass",
  "limitations": [
    "not physical-device acceptance",
    "AVD PAGE_SIZE is 4096, not 16384",
    "no 16 KB compatibility conclusion",
    "no Auth-issued/live backend, Storage, release signing, publication, or production activity"
  ],
  "task_ids": [
    "QA-001",
    "AND-001",
    "AND-002",
    "AND-003",
    "AND-004"
  ],
  "timestamp": "2026-11-04T05:30:45+08:00",
  "dirty_tree": true,
  "checks": [
    {
      "category": "and001-exact-reminder-reboot-and-delivery-emulator",
      "outcome": "passed"
    },
    {
      "category": "and001-inexact-fallback-delivery-emulator",
      "outcome": "passed"
    },
    {
      "category": "and002-backup-manager-refuses-package-backup",
      "outcome": "passed"
    },
    {
      "category": "and002-cross-device-restore",
      "outcome": "unverified"
    },
    {
      "category": "and003-camera-permission-denial-and-draft-restart-emulator",
      "outcome": "passed"
    },
    {
      "category": "and003-picker-activity-loss-and-gallery-handoff",
      "outcome": "unverified"
    },
    {
      "category": "and004-seeded-100-tabs-10000-entries-emulator-ui-timing",
      "outcome": "passed"
    },
    {
      "category": "and004-low-memory-and-16kb-device-profile",
      "outcome": "unverified"
    },
    {
      "category": "flutter-analysis",
      "outcome": "passed"
    },
    {
      "category": "flutter-regression-suite-650",
      "outcome": "passed"
    },
    {
      "category": "physical-device-and-release-signing",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

## AND-001 ? scheduled reminder and reboot

On emulator `emulator-5554` (API 37, x86_64; `sys.boot_completed=1`), the integration harness scheduled a synthetic reminder using Tabby's notification service. Before reboot, `dumpsys alarm` showed a Tabby `RTC_WAKEUP` scheduled-notification receiver alarm with `window=0` for 21:10:17. After `adb reboot`, logcat showed `com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver` starting at 21:07:38; `dumpsys alarm` again showed the same reminder pending. At 21:10:31, `dumpsys notification --noredact` showed an active `com.zalweb.tabby` NotificationRecord, ID 794072101, channel `tabby_reminders`, title ?Payment due today?, for the synthetic PHP 12.34 reminder.

The exact-alarm-denied fallback was separately exercised after turning off the Android ?Alarms & reminders? special-access switch in Settings. The service reported exact access false, and `dumpsys alarm` showed a windowed RTC_WAKEUP (`window=+52s314ms`) due 21:14:26. At 21:15:20, Android notification manager showed the synthetic PHP 1.01 ?Payment due today? notification. Exact-alarm access was restored afterward.

Setup note: `appops SCHEDULE_EXACT_ALARM deny` alone did not change the special-access state and the first fallback assertion failed as expected. The actual Settings switch was then disabled; the repeat observed `exactAccess=false` and delivered the inexact notification. This initial setup failure is not counted as product behavior failure.

**Observed:** scheduled notification, reboot receiver re-arming, post-reboot delivery, and inexact fallback delivery passed on this AVD. Notification permission denial, user tap/deep-link handling, package replacement, OEM battery behavior and physical-device delivery remain untested.

## AND-002 ? Android backup exclusion

The harness wrote and read back a synthetic sentinel through `FlutterSecureStorage`. With Android Backup Manager enabled (`adb shell bmgr enable true`), `adb shell bmgr backupnow com.zalweb.tabby` returned:

```text
Running incremental backup for 1 requested packages.
Package com.zalweb.tabby with result: Backup is not allowed
Backup finished with result: Success
```

Android refused package backup, consistent with `allowBackup=false`. This is an end-to-end emulator Backup Manager eligibility result, beyond manifest inspection. No backup dataset restore or cross-device recovery was performed; keys, archives, recovery UI and OEM/API-specific restore behavior remain open.

## AND-003 ? picker denial and draft preservation

A synthetic `FormDraftStore` payment draft was written to secure storage. The real Android camera permission prompt was shown and ?Don?t allow? selected. `ImagePicker().pickImage(source: ImageSource.camera)` returned a caught `PlatformException`; the draft read immediately afterward matched the stored draft (`draftPreserved=true`). After the device reboot, a separate integration run read the same draft and passed (`DEVICE_ACCEPTANCE_DRAFT_RESTART preserved=true`).

This proves permission-denial handling at the plugin/store harness boundary and encrypted draft persistence across reboot. It does not exercise the full authenticated form, gallery result handoff, Android activity destruction during the picker, or process-kill recovery while a picker is open.

## AND-004 ? seeded history scale

The integration test seeded 100 synthetic tabs with 100 entries each (10,000 entries in memory), rendered the actual `TabDetailScreen` for one tab (100 entries), and opened the older-record page to record 50. Two emulator harness measurements:

| Run | Seed construction | First-page render/settle | Reveal older 50 |
|---|---:|---:|---:|
| A | 147 ms | 1,341 ms | 402 ms |
| B | 184 ms | 1,688 ms | 346 ms |

These are integration-test wall times on the API 37 AVD, not frame-time benchmarks. The records were synthetic and in-memory; this did not measure PostgREST/local database loading, cold start, low-memory pressure, or interrupted migration. AVD reports 4,005,308 kB total and 2,060,740 kB available RAM, so it is not representative of a low-memory device. `getconf PAGE_SIZE` returned **4096**; 16 KB compatibility remains unverified.

## Evidence

## Commands and environment outcomes

- `flutter analyze --no-pub` at 2026-11-04T05:30:45+08:00: passed, ?No issues found!? (29.2s).
- `flutter test --no-pub` at 2026-11-04T05:30:45+08:00: passed, 650/650 (50s).
- Main emulator integration target: all tests passed; app left running. Separate draft-after-reboot target passed. Inexact-fallback target passed and the delivered notification was observed through Android notification manager.
- `adb devices`: `emulator-5554 device`; `sys.boot_completed=1`; `pm path com.zalweb.tabby` returned the installed package path.
- The AVD had no active default network (airplane mode enabled). No live or production request/write, Supabase/Auth/Storage action, signing, release dispatch, deployment or publication occurred. A CDN DNS lookup failed offline; no connection was established.
- M2 remains disabled. QA-001 remains `in_progress`; AND-001..004 remain `implemented`; REL-001 remains open. Physical-hardware requirements (OEM battery optimization, real FCM, GCash/Maya deep links) remain unverified. AND-005/release signing stays open pending authorized signing identity. All 16 KB assertions stay open.

## Limits and next action

Keep AND-001..004 implemented until required device checks pass. Continue the emulator matrix where meaningful; obtain physical hardware for OEM battery behavior, FCM, payment-app deep links, low-memory performance and 16 KB validation. Keep AND-005 signing and REL-001 open until an authorized signing identity and remaining release gates are available. QA-001 remains in progress; live backend/Auth/Storage and production gates remain open.
