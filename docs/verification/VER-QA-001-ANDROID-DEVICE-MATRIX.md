# VER-QA-001 — Android emulator device-matrix tranche

```json verification-metadata
{
  "id": "VER-QA-001-ANDROID-DEVICE-MATRIX",
  "tasks": ["QA-001", "SEC-001", "SEC-003", "HOME-001", "HOME-002", "HOME-003", "HOME-004"],
  "task_ids": ["QA-001", "SEC-001", "SEC-003", "HOME-001", "HOME-002", "HOME-003", "HOME-004"],
  "timestamp": "2026-11-04T06:10:00+08:00",
  "tested_commit": "33a89e8c37394f0e7d4983f98d9e1458982015ea",
  "dirty_tree": true,
  "platform": "Windows; Android emulator Medium_Phone_API_37.0; emulator-5554; API 37; x86_64",
  "environment": "Emulator-only integration_test with Android secure storage and notification APIs; synthetic fixtures; no Auth-issued identity",
  "commands": [
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_device_matrix_seed_test.dart -d emulator-5554 --keep-app-running",
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_device_matrix_test.dart -d emulator-5554 --keep-app-running",
    "adb shell am force-stop com.zalweb.tabby",
    "adb shell input keyevent HOME",
    "adb shell dumpsys notification --noredact",
    "adb shell dumpsys alarm",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub"
  ],
  "checks": [
    {"category": "SEC-001-cold-lock", "outcome": "passed"},
    {"category": "SEC-001-pin-navigator-recovery", "outcome": "failed"},
    {"category": "SEC-003-pin-throttle-emulator", "outcome": "passed"},
    {"category": "HOME-001-dashboard-filters-emulator", "outcome": "passed"},
    {"category": "HOME-002-settled-reminder-refresh-emulator", "outcome": "passed"},
    {"category": "HOME-003-permission-and-preferences-emulator", "outcome": "passed"},
    {"category": "HOME-004-background-force-stop-delivery-emulator", "outcome": "failed"},
    {"category": "flutter-analysis", "outcome": "passed"},
    {"category": "flutter-suite", "outcome": "passed"}
  ],
  "result": "partial_pass",
  "limitations": [
    "emulator evidence only, not physical-device acceptance",
    "AVD PAGE_SIZE is 4096; 16 KB compatibility remains unverified",
    "no live/Auth-issued backend, Storage, release signing, production mutation, deployment, or publication"
  ]
}
```

**Run:** 2026-11-04, Asia/Manila (UTC+08:00)  
**Branch/base:** `codex/m1-application-fixes`, `33a89e8c37394f0e7d4983f98d9e1458982015ea`  
**Device:** existing `Medium_Phone_API_37.0`, `emulator-5554`, Android API 37, x86_64, `PAGE_SIZE=4096`.  
**Method:** existing `integration_test` and `test_driver/integration_test.dart`; real Android secure storage, permission APIs, notification scheduling, `adb` force-stop/home actions, and widget harnesses with synthetic in-memory ledger data. Emulator evidence only.

## Expected and actual results

| Check | Result and measured evidence |
|---|---|
| SEC-001 cold launch | Seed integration persisted PIN `1234` for synthetic account `device-matrix-sec001`. `adb shell am force-stop com.zalweb.tabby` returned no PID; a fresh Flutter integration process then loaded the PIN (`persistedPinVerifies=true`), displayed `Tabby is locked`, and kept `Protected synthetic ledger` absent. The navigator recovery assertion failed in three repetitions: after entering `1234` and invoking/tapping `Unlock with PIN`, the protected child remained absent and inline error was `null`. Cold lock bypass was not observed; PIN navigator recovery is a reproducible emulator failure. |
| SEC-003 throttling | Five consecutive incorrect PIN checks took 3,555, 3,036, 3,027, 3,117, and 3,070 ms in the final run. The next attempt was locked for 26.931 seconds; a new service instance still observed the lock. An earlier run measured 3,019/3,031/3,305/2,902/2,998 ms and 27.0 seconds remaining. Emulator-only pass. |
| HOME-001 dashboard | Real dashboard widget rendered synthetic balances: `You are owed` = 5,000 centavos and `You owe` = 2,300 centavos. Calendar month returned 1 activity, last 7 days returned 2, and the future-dated item was excluded. Emulator widget-harness pass; data was synthetic and in-memory, not a live account refresh. |
| HOME-002 settled reminder refresh | With Android notification permission granted, the synthetic settled-tab reminder alarm existed before refresh; `refreshDueReminders()` returned 0 rows and removed the alarm (`postRefreshRows=0 alarmStillPending=false`). Emulator local-provider pass; no live backend refresh was claimed. |
| HOME-003 permission/preferences | With `POST_NOTIFICATIONS` granted, enabled preference produced a pending alarm and disabling the preference removed it (`true/true/false`). A separate run after Android revoked permission during package install observed `permissionGranted=false` and no enabled/disabled probe alarm (`false/false/false`). After explicitly granting permission again, the final run repeated `true/true/false`. Emulator-only permission and preference gating pass. |
| HOME-004 background/force-stop | With permission granted, integration scheduled probes due at 22:02:29.293839 and 22:02:59.404389 device time. The app was backgrounded at 22:01:49; at 22:03:02 no matching notification was present (at least 33 seconds after the first due time). The scheduled receiver alarm for the force-stop probe remained pending. `am force-stop` at 22:03:02 left no app PID; at 22:03:47 (45 seconds after the second due time) there was still no matching notification. Background and force-stop delivery did not pass this observation window; delivery remains open and must be investigated. |

## Evidence

The scenario table above is based on device logs, integration-test assertions, Android package permission state, pending-alarm inventory and notification records. The AVD clock was approximately 8 hours behind the Windows host timezone; all observation times below are emulator device time. No account credentials or live user data were used.

### Commands and actual run outcomes

- `C:\src\flutter\bin\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_device_matrix_seed_test.dart -d emulator-5554 --keep-app-running` — passed, one seed test; log `DEVICE_MATRIX_SEC001 seedPersisted=true account=device-matrix-sec001`.
- `C:\src\flutter\bin\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_device_matrix_test.dart -d emulator-5554` — failed SEC-001 recovery; remaining tests reported SEC-003, HOME-001, HOME-002, HOME-003 and scheduled HOME-004 probes. Permission was false in that run, so HOME-002's expected pre-refresh alarm was absent.
- Same matrix command with `--keep-app-running` — failed SEC-001 PIN-recovery assertion; SEC-003, HOME-001, HOME-002 and HOME-003 passed; HOME-004 probes were scheduled. A preceding run without a fresh seed failed SEC-001 setup and HOME-002 setup because the PIN and notification permission were not present after installation.
- `adb shell pm grant com.zalweb.tabby android.permission.POST_NOTIFICATIONS` — succeeded; `dumpsys package` showed `granted=true` before the final matrix run.
- `adb shell input keyevent HOME` — launcher became `topResumedActivity`; emulator clock was 22:01:49.
- `adb shell am force-stop com.zalweb.tabby` — package process stopped; `pidof` returned no PID.
- `adb shell getconf PAGE_SIZE` — `4096`.
- `adb devices -l` — `emulator-5554` in `device` state.
- `C:\src\flutter\bin\flutter.bat analyze --no-pub` — passed, `No issues found!` (35.4 seconds).
- `C:\src\flutter\bin\flutter.bat test --no-pub` — passed, 650/650 (52 seconds).

The matrix covered seven assertions: five passed (SEC-001 cold lock, SEC-003 throttling, HOME-001, HOME-002, HOME-003) and two failed (SEC-001 navigator recovery and HOME-004 delivery). The overall matrix command therefore exited nonzero. No physical device, live Supabase/Auth-issued journey, release signing identity, Storage, deployment, publication, or production mutation was used. GRP/PAY/SEC-005 API journeys were outside this device tranche and remain deferred.

## Limits and next action

- SEC-001 is implemented, not verified: investigate why the successfully verified cold PIN does not unlock the integration gate; repeat on a physical device.
- HOME-004 is implemented, not verified: inspect scheduled receiver delivery/notification history for background and force-stop; allow a wider inexact-alarm window in a follow-up run.
- HOME-001/HOME-002/HOME-003 emulator assertions do not substitute for real account data, server refresh, physical-device behavior, or live backend acceptance.
- The AVD is 4 KB page size; it cannot prove 16 KB compatibility. Physical OEM battery behavior, FCM and GCash/Maya deep links remain unverified.
- AND-005 and REL-001 remain open without an authorized signing identity. QA-001 remains `in_progress`; M2 remains disabled. Production and live Supabase were untouched.
