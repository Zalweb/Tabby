# VER-AND-005 — Fail-closed Android publication gates

```json verification-metadata
{
  "id": "VER-AND-005",
  "task_ids": [
    "AND-005"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "workflow-source",
      "outcome": "passed"
    },
    {
      "category": "android-build",
      "outcome": "passed"
    },
    {
      "category": "artifact-rejection",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "release-artifact",
      "outcome": "unverified"
    },
    {
      "category": "upgrade",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T19:25:40.018Z",
  "tested_commit": "c90a1efefce53393d0068147ba3c8923e421ad6b",
  "dirty_tree": true,
  "environment": "Windows; Node 26.13; Android SDK build-tools 36.0.0, actual apksigner/zipalign, Android Studio JBR/Gradle; Flutter 3.47.8 debug packaging. Isolated yaml 2.8.1 parser and synthetic Node fixtures; no production key, GitHub runner/environment execution, live backend or device.",
  "commands": [
    "node --test scripts/android-release.test.cjs scripts/check-project-memory.test.cjs",
    "node scripts/verify-android-artifact.cjs --apk build/app/outputs/flutter-apk/app-debug.apk --sdk <local-sdk> --java <local-java> --expected-cert <synthetic-hex> --commit <base> (expected rejection)",
    "gradlew.bat :app:assembleRelease --dry-run (expected signing rejection)",
    "flutter build apk --debug",
    "flutter test test/platform_configuration_test.dart",
    "zipalign -c -P 16 4 build/app/outputs/flutter-apk/app-debug.apk",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Node release/documentation regressions passed 13/13, including eight new artifact/candidate/workflow tests. Six workflow documents parsed with YAML 1.2. Actual debug APK rejected by apksigner certificate inspection. Actual Gradle release task graph refused missing signing; normal debug APK still built successfully in 50.7 seconds. Seven ARM64/x86-64 libraries and actual debug ZIP passed source 16 KB alignment checks. Flutter platform configuration suite passed 5/5; latest full Flutter application suite remains 367/367 from VER-QR-006, with no Dart application changes in this batch.

## Evidence

[Artifact verifier](../../scripts/verify-android-artifact.cjs) invokes Android tools and parses actual ZIP/ELF headers. [Candidate gate](../../scripts/check-release-gate.cjs) binds evidence to exact commit/digest/certificate and open task inventory. [Regressions](../../scripts/android-release.test.cjs) exercise positive synthetic shapes, rejection cases and all publication paths. [Publication contract](../releases/README.md) records operational requirements; no passing release candidate file is fabricated. Actual debug certificate rejection and missing-signing task-graph rejection passed; debug packaging is preserved.

## Limits and next action

Static/synthetic workflow tests do not establish GitHub environment protection or live CI execution. Debug ELF/ZIP alignment is not a signed candidate or 16 KB runtime result. Production signing/upgrade/OAuth/device/backend/publication remain open; no release approval.
