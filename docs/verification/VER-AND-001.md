# VER-AND-001 — Android scheduling foundation

```json verification-metadata
{
  "id": "VER-AND-001",
  "task_ids": [
    "AND-001"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "android-build",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T13:20:14.569Z",
  "tested_commit": "4897c8090b035f3fc3bbf6c5edb68c56b654635d",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; flutter_local_notifications 22.3.1; Android Gradle debug build. No connected adb devices.",
  "commands": [
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "adb devices -l",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 4897c8090b035f3fc3bbf6c5edb68c56b654635d",
    "git diff --check"
  ]
}
```

## Expected and actual results

Full suite 275/275 passed. Analysis: No issues found. Debug APK build succeeded in 50.0s. Six policy tests cover granted/denied access, capability errors, permission revocation race, unrelated failure propagation and non-Android behavior. Configuration regression verifies private receivers and boot/package-replacement integration. Packaged manifest independently inspected and includes the expected components. adb reports no attached devices.

## Evidence

Installed flutter_local_notifications 22.3.1 README and API implementation reviewed before changes. Final debug artifact: build/app/outputs/flutter-apk/app-debug.apk, SHA256 40923b6de5a52561cf6fb0144184d99f47cd487cf20c355912ed6b05db2e715f. Packaged manifest: build/app/intermediates/packaged_manifests/debug/processDebugManifestForPackage/AndroidManifest.xml. Existing package_info_plus Kotlin Gradle migration warning remains, without build failure. These are debug packaging and mocked policy tests, not device evidence.

## Limits and next action

No device/emulator connected; permission dialogs/settings return, reboot, actual due reminder/tap and closed-app delivery unverified. Current caller flows do not invoke the scheduling/permission service; HOME integration remains. No APK installation, backend migration, signing approval, deployment or publication performed. Task remains in_progress until caller integration and device acceptance are recorded.

- 2026-10-31T13:42:59.823Z — Superseding source correction: dashboard refresh already invokes scheduleDueReminder. The earlier claim that scheduling had no caller was incorrect. Notification preference enforcement and explicit permission opt-in wiring remain in HOME-003, and device reboot/delivery/tap checks remain unverified.
