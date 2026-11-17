# VER-QA-001-ANDROID-EMULATOR — Android emulator smoke checks

```json verification-metadata
{
  "id": "VER-QA-001-ANDROID-EMULATOR",
  "task_ids": ["QA-001", "AND-001", "AND-002", "AND-003", "AND-004", "AND-005"],
  "tested_commit": "b156ed97677b92187731bee3992f16555e56e155",
  "dirty_tree": true,
  "timestamp": "2026-11-04T04:38:57+08:00",
  "agent": "Codex root",
  "platform": "Windows / Android emulator",
  "environment": "Existing Medium_Phone_API_37.0 AVD; Android 17 / API 37; sdk_gphone64_x86_64; 4,005,308 kB RAM; TalkBack enabled; airplane mode and Wi-Fi/mobile data disabled; installed pre-existing local debug APK, SHA-256 1F42052734948C10F54172D32FF8F9D5257DF4CDFA3BFFC70717197F407E5AA4",
  "evidence_type": "Android emulator smoke and package configuration checks; not physical-device or release-candidate acceptance",
  "commands": [
    "emulator.exe -avd Medium_Phone_API_37.0 -no-audio -no-boot-anim -netdelay none -netspeed full",
    "adb wait-for-device; adb shell getprop sys.boot_completed",
    "adb shell settings put secure enabled_accessibility_services com.google.android.marvin.talkback/.TalkBackService",
    "adb shell settings put secure accessibility_enabled 1",
    "adb shell settings put global airplane_mode_on 1; adb shell svc wifi disable; adb shell svc data disable",
    "apksigner.bat verify --print-certs build/app/outputs/flutter-apk/app-debug.apk",
    "adb install -r build/app/outputs/flutter-apk/app-debug.apk",
    "adb shell monkey -p com.zalweb.tabby 1",
    "adb shell cmd package query-receivers --components -a android.intent.action.BOOT_COMPLETED -p com.zalweb.tabby",
    "aapt2.exe dump xmltree build/app/outputs/flutter-apk/app-debug.apk --file AndroidManifest.xml",
    "C:\\src\\flutter\\bin\\flutter.bat build apk --release --no-pub (expected fail-closed signing guard)",
    "Push-Location android; .\\gradlew.bat :app:testDebugUnitTest --no-daemon",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub",
    "node scripts/test-backend-native.cjs"
  ],
  "checks": [
    {"category":"android-emulator-boot","outcome":"passed"},
    {"category":"android-emulator-talkback-semantics-smoke","outcome":"passed"},
    {"category":"android-emulator-boot-receiver-package-resolution","outcome":"passed"},
    {"category":"android-emulator-backup-manifest-configuration","outcome":"passed"},
    {"category":"and005-release-signing-fails-closed-without-credentials","outcome":"passed"},
    {"category":"android-kotlin-unit-tests","outcome":"passed"},
    {"category":"native-postgresql-regression-harness","outcome":"passed"},
    {"category":"flutter-analysis","outcome":"passed"},
    {"category":"flutter-regression-suite","outcome":"passed"},
    {"category":"and001-scheduled-notification-delivery-and-reboot","outcome":"unverified"},
    {"category":"and002-cross-device-backup-restore-and-recovery","outcome":"unverified"},
    {"category":"and003-native-picker-process-recovery-and-draft-protection","outcome":"unverified"},
    {"category":"and004-low-memory-100-tabs-10000-record-profile","outcome":"unverified"},
    {"category":"and005-release-signed-candidate-upgrade-oauth-and-16kb-runtime","outcome":"unverified"},
    {"category":"physical-device","outcome":"unverified"},
    {"category":"live-backend-and-auth-issued","outcome":"unverified"}
  ]
}
```

## Expected and actual results

The existing `Medium_Phone_API_37.0` AVD booted on `emulator-5554`; `sys.boot_completed=1`, Android release `17`, API `37`, model `sdk_gphone64_x86_64`, and `ro.kernel.qemu=1`. It has 4,005,308 kB total memory (2,060,740 kB available at the final probe), so it does not meet the low-memory profile target. TalkBack is installed and enabled; Android reported `touchExplorationEnabled=true`. With the pre-existing debug app at its onboarding screen, TalkBack focused the `Skip` control. A screenshot is retained at [emulator onboarding with TalkBack](assets/qa001-medium-phone-api37-talkback-onboarding.png), SHA-256 `BA163B70624BA07C49B9659BE8ECD0020D3E4E73CC4D46179E22DE6FD71AC3C6`. `uiautomator dump` did not complete while TalkBack was active (`ERROR: could not get idle state`); screenshot/focus is the captured smoke evidence, not a full semantics audit.

The emulator was isolated before app launch: Wi-Fi/mobile data were disabled, airplane-mode setting was `1`, and `dumpsys connectivity` reported `Active default network: none`. The package manager resolved `com.zalweb.tabby/com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver` for `BOOT_COMPLETED`. The installed package was version `1.0.4` / versionCode `5`. There were no Tabby alarm entries and `cmd appops get ... SCHEDULE_EXACT_ALARM` reported `No operations`; no reminder was actually scheduled or delivered.

The pre-existing debug APK was 241,187,598 bytes, last modified 2026-11-02 04:48:30 +08:00. Its SHA-256 is `1F42052734948C10F54172D32FF8F9D5257DF4CDFA3BFFC70717197F407E5AA4`; `apksigner verify --print-certs` identified `CN=Android Debug`, certificate SHA-256 `1106adbd9a5c4d1bc275c07eb1322b09551c628c11a3f855873bc349c150ec3e`. Its source commit is not attested, so this is only an offline smoke artifact, not an exact-current-commit build or release candidate. No APK was built or signed during this tranche.

`aapt2 dump xmltree` on that APK confirmed `allowBackup=false`, `fullBackupContent` and Android 12+ `dataExtractionRules` references, `SCHEDULE_EXACT_ALARM`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, the scheduled-notification boot receiver, and its `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` filters. The emulator's Backup Manager is disabled, so cloud backup/device-transfer and restore behavior did not run.

`flutter build apk --release --no-pub` exited 1 in 11 seconds with `Release signing is required; debug signing is never a release fallback.` `android/key.properties` is absent; no signing credentials were inspected. No release APK was produced. `:app:testDebugUnitTest --no-daemon` passed 2/2 JVM Kotlin tests (PushEnvelopeTest); this compiles native sources but is not emulator instrumentation. Flutter analysis passed with no issues, the full Flutter suite passed 650/650, and `node scripts/test-backend-native.cjs` passed on local native PostgreSQL 17.11, including its concurrency contracts.

## Evidence

This record captures only checks actually run against the emulator and local test harnesses. TalkBack/onboarding and installed-package probes used a pre-existing debug APK; no authenticated app session was created. The screenshot is the only committed emulator capture. The first `apksigner` invocation lacked `JAVA_HOME`; retry with Android Studio's bundled JBR succeeded. The first Gradle invocation used the repository root and failed because it is not the Gradle root; the corrected invocation from `android/` passed. The first `uiautomator dump` attempt timed out and the next returned `could not get idle state` while TalkBack was enabled.

## Limits and next action

All five AND tasks remain `implemented`; this partial emulator evidence does not satisfy their full `android-device` acceptance. AND-001 still needs actual scheduled notification permission allow/deny, firing, reboot/package-update restoration and tap behavior. AND-002 needs an enabled backup transport or second device and an actual restore/recovery journey. AND-003 needs native picker interruption/recreation, lost-data recovery and draft/back checks. AND-004 needs the 100-tab/10,000-record profile on a low-memory target and interrupted migration exercise. AND-005 needs an authorized, properly signed exact candidate, install/upgrade/data-preservation/OAuth and 16 KB runtime checks. No physical device was attached or claimed.

QA-001 stays `in_progress`; REL-001 stays `in_progress`. Live Supabase/Auth-issued, Storage, production, deployment and publication gates remain open; M2 stays disabled. The emulator remained offline and no live or production request/write occurred.
