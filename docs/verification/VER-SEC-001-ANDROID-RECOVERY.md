# VER-SEC-001-ANDROID-RECOVERY — API 37 emulator PIN recovery

```json verification-metadata
{
  "id": "VER-SEC-001-ANDROID-RECOVERY",
  "task_ids": ["SEC-001", "QA-001"],
  "tasks": ["SEC-001", "QA-001"],
  "tested_commit": "6d3cbb26634295d1f95095e92185d8cfdafb7364",
  "dirty_tree": true,
  "timestamp": "2026-11-04T06:36:38+08:00",
  "agent": "Codex root / Windows",
  "platform": "Windows; Android emulator Medium_Phone_API_37.0; emulator-5554; API 37; x86_64; PAGE_SIZE 4096",
  "environment": "Flutter integration_test with real Android secure storage; synthetic account and PIN only; emulator evidence, not physical-device acceptance",
  "commands": [
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_sec001_recovery_test.dart -d emulator-5554 --keep-app-running",
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_device_matrix_seed_test.dart -d emulator-5554 --keep-app-running",
    "C:\\src\\flutter\\bin\\flutter.bat drive --driver=test_driver/integration_test.dart --target=integration_test/android_device_matrix_test.dart -d emulator-5554 --keep-app-running",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub"
  ],
  "checks": [
    {"category": "sec001-widget-regression", "outcome": "passed"},
    {"category": "sec001-api37-emulator-recovery", "outcome": "passed"},
    {"category": "flutter-analysis", "outcome": "passed"},
    {"category": "flutter-suite", "outcome": "passed"}
  ],
  "result": "passed",
  "limitations": [
    "emulator-only; no physical-device acceptance",
    "PAGE_SIZE is 4096; 16 KB compatibility remains unverified",
    "no production/live Supabase, Auth-issued identity, Storage, signing, release, deployment or publication",
    "HOME-004 background and force-stop notification delivery remains failed and was not modified",
    "GRP-001..005, PAY-001 and SEC-005 local PostgREST HTTP journeys remain unexercised"
  ]
}
```

## Expected and actual results

The reported path was a valid PIN entered after an `adb` force-stop and a cold process launch. The synthetic PIN remained in Android secure storage, `PinProtectionService.verifyPin` returned `true`, the lock screen appeared, and protected content stayed hidden. The original matrix then checked for the protected child after a fixed four-second delay and reported failure (`inlineError=null`).

The focused trace showed the gate's captured session was still current and its valid-result path set `_locked=false`; the protected child appeared after the real secure-storage/KDF verification completed. Repeated completion times were 4.690, 4.974, 5.174 and 7.654 seconds. Thus the reproduced failure was the harness's four-second timing assumption, not navigator routing, PIN verification, an unlock/cache reset, or a recovery prompt. A separate earlier focused test had also double-disposed a provider-owned settings notifier after recovery; that was test cleanup and was removed. The recovery UI now exposes an accessible “Verifying PIN” progress state while the real verification is pending, so this latency no longer looks like a dead button.

## Results

| Assertion | Before | After |
|---|---|---|
| Cold lock after fresh process | Persisted PIN loaded; lock visible; protected child absent | Same; deterministic regression passes |
| Valid PIN recovery | Three matrix repetitions were declared failed at the fixed four-second cutoff; no inline error was present | Focused emulator runs unlocked in 4.690–7.654 seconds; protected child visible |
| Resume/relock recovery | Not established by prior failing matrix | Final matrix re-locked on pause and recovered after resume; unlock measured 5.147 seconds |
| Full matrix cold unlock | Earlier run reported failure | Final run measured 5.032 seconds; bounded wait and progress assertion passed |
| Widget regression | No pending-verification coverage | Completer-backed test verifies progress appears while verification is pending, private content remains hidden, then progress clears and content appears after success |
| Flutter analysis | — | `flutter analyze --no-pub`: passed, no issues |
| Full Flutter suite | 650 tests on previous baseline | `flutter test --no-pub`: passed, 651/651 |

The focused recovery scenario was repeated three times after the initial 7.654-second trace; the full matrix then passed SEC-001 cold and resume/relock recovery alongside the other in-scope matrix checks. No source changes were made to HOME-004. Its background/force-stop delivery failure remains open exactly as recorded in [VER-QA-001-ANDROID-DEVICE-MATRIX](VER-QA-001-ANDROID-DEVICE-MATRIX.md).

## Evidence

Observed output included `SEC001_REPRO persistedPinValid=true gateUnlockMs=... protectedVisible=true`; the device matrix logged `lockedColdStart=true protectedHidden=true`, measured cold gate unlock and confirmed resume/relock recovery. Flutter analysis output was `No issues found!`; the full suite ended `All tests passed!` at 651/651. Toolchain: Flutter SDK at `C:\src\flutter\bin\flutter.bat` on Windows; Android AVD API 37, x86_64. Regression source: [cold-lock widget test](../../test/features/cold_lock_test.dart), [focused emulator recovery test](../../integration_test/android_sec001_recovery_test.dart), and [device matrix](../../integration_test/android_device_matrix_test.dart).

## Regression coverage

- `integration_test/android_sec001_recovery_test.dart` verifies the persisted synthetic PIN, cold locked screen, visible verification progress and eventual protected-child recovery with a 20-second bounded wait.
- `integration_test/android_device_matrix_test.dart` retains the cold process and simulated resume/relock path, checks the progress state, and waits for actual recovery rather than assuming a four-second completion.
- `test/features/cold_lock_test.dart` holds verification pending with a `Completer`, confirms private content remains hidden while the status is visible, and confirms successful verification reveals the private child.

## Limits and next action

This is API 37 emulator evidence only. It does not establish physical Android behavior, cross-device restore, OEM lifecycle behavior, live/Auth-issued access, 16 KB page compatibility, release signing, or a closed QA-001 gate. `PAGE_SIZE` is 4096. QA-001 remains `in_progress`; REL-001 remains open; M2 remains disabled. Continue physical-device and remaining SEC-001 acceptance when available. Keep HOME-004 as a separate fix target. The deferred GRP-001..005, PAY-001 and SEC-005 local HTTP journeys have not been exercised and remain the next API tranche.
