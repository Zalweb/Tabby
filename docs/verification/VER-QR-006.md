# VER-QR-006 — Android QR export and friend profile access

```json verification-metadata
{
  "id": "VER-QR-006",
  "task_ids": [
    "QR-006"
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
      "category": "backend-authorization",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T19:14:45.701Z",
  "tested_commit": "3c2bb5c133fac14859f21ff8be12c12f010329e3",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8; synthetic QR images and MethodChannel/repository test boundaries; actual Android debug Gradle/Kotlin packaging. No attached device, real wallet or live backend.",
  "commands": [
    "flutter test test/features/receiving_qr_export_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "adb devices -l",
    "Get-FileHash build/app/outputs/flutter-apk/app-debug.apk -Algorithm SHA256",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 367/367; export-focused suite passed 8/8; Dart analysis clean. Android debug APK built successfully in 108 seconds, compiling new Kotlin/manifest/FileProvider code. adb devices -l reported no attached devices. Existing native role acceptance from VER-QR-002/003 covers method authorization; no new SQL in this batch.

## Evidence

[Export/profile regressions](../../test/features/receiving_qr_export_test.dart) cover validated bytes, cancel/error, unauthorized/invalid inputs, stale account, unsupported platform, fullscreen and read-only profile entry. [Android bridge](../../android/app/src/main/kotlin/com/zalweb/tabby/MainActivity.kt) uses document creation and temporary read-only content URIs. FileProvider exposes only receiving-qr cache. Debug APK SHA-256: 3ec2f9f4f8bbe21c09ee7c043996f3bd5b256fa8751daead79866cef4d21bbcc; dirty source over recorded base, not a release candidate. Reviewed [Android sharing guidance](https://developer.android.com/training/secure-file-sharing) and [system document saving](https://developer.android.com/training/data-storage/shared/documents-files).

## Limits and next action

MethodChannel tests are not native runtime tests. Debug packaging is not device wallet acceptance, signed upgrade, 16 KB compatibility or release approval. No deployment/publication; keep live/device gates open.
