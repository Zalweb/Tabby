# REL-001 local candidate validation

```json verification-metadata
{
  "id": "VER-REL-001-LOCAL-CANDIDATE",
  "task_ids": ["REL-001", "AND-005", "QA-001"],
  "tested_commit": "0ade0a5010d4f4a9ec67d60f1485b8769085bddb",
  "dirty_tree": false,
  "timestamp": "2026-11-04T03:29:47+08:00",
  "environment": "Windows; clean git-archive source snapshot; Flutter 3.47.8 / Dart 3.13.7; Android SDK build-tools 36.0.0; Android Studio JBR; Node 26.13",
  "debug_apk_sha256": "ee3b29513b6f94d8d24676b70272c8f66f0f8f28244fd58669fbb4e94a7bdc55",
  "checks": [
    {"category": "workflow-source", "outcome": "passed"},
    {"category": "workflow-tests", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "regression", "outcome": "passed"},
    {"category": "android-debug-build", "outcome": "passed"},
    {"category": "version-alignment", "outcome": "passed"},
    {"category": "web-build", "outcome": "passed"},
    {"category": "apk-zipalign-16kb", "outcome": "passed"},
    {"category": "native-elf-alignment-16kb", "outcome": "passed"},
    {"category": "debug-artifact-rejection", "outcome": "passed"},
    {"category": "release-signing-guard", "outcome": "passed"},
    {"category": "web-browser-test", "outcome": "unverified"},
    {"category": "release-artifact", "outcome": "unverified"},
    {"category": "upgrade", "outcome": "unverified"},
    {"category": "oauth", "outcome": "unverified"},
    {"category": "16kb-device", "outcome": "unverified"},
    {"category": "android-device", "outcome": "unverified"},
    {"category": "release-authorization", "outcome": "unverified"}
  ],
  "commands": [
    "C:\\src\\flutter\\bin\\flutter.bat pub get --offline",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat build apk --debug --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat build web --release --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub --platform chrome test/features/web_responsive_test.dart",
    "android/gradlew.bat :app:assembleRelease --dry-run --offline",
    "node --test scripts/android-release.test.cjs scripts/check-project-memory.test.cjs",
    "node scripts/verify-android-artifact.cjs (against local debug APK; expected rejection)",
    "aapt2 dump badging; zipalign -c -P 16 4; nativeLibraries() on local debug APK",
    "adb devices -l"
  ]
}
```

## Expected and actual results

Candidate source revision inspected and built: `0ade0a5010d4f4a9ec67d60f1485b8769085bddb` (`0ade0a5`). A clean `git archive` of that tracked source was used in ignored `.dart_tool/rel001-source-only/`; untracked local signing files and credentials were not copied or read.

- Release configuration is fail-closed. `android/app/build.gradle.kts` reads `android/key.properties` only when present and rejects any release task graph without all four nonblank properties and an existing keystore. No debug signing fallback is configured. The isolated source archive contained no tracked key properties/keystore; `:app:assembleRelease --dry-run --offline` stopped with `Release signing is required; debug signing is never a release fallback.` No signing credential or certificate was used or read.
- `.github/workflows/build-android.yml` requires four GitHub signing secrets, writes the keystore and properties only in its runner workspace, builds `--release`, verifies the configured certificate/package/version/ZIP/ELF, then uploads a private build artifact. `build-mobile.yml` may run on main/tag/manual dispatch but delegates to private artifact build only. The sole release publisher is `publish-latest-build.yml`, invoked by manual `publish-release-apk.yml` on main after run/commit provenance and exact candidate evidence checks. No workflow was run or dispatched.
- `pubspec.yaml` declares `1.0.4+5`; Gradle sources `versionName`/`versionCode` from Flutter. `aapt2 dump badging` on the local debug build reported `com.zalweb.tabby`, `versionName='1.0.4'`, `versionCode='5'`: aligned.
- Flutter 3.47.8 debug build succeeded in 140.4 seconds. Its SHA-256 is `EE3B29513B6F94D8D24676B70272C8F66F0F8F28244FD58669FBB4E94A7BDC55`. This digest identifies a debug APK only; it is not a signed release candidate. The actual artifact verifier rejected it with `Debug signing certificate is forbidden`.
- `zipalign -c -P 16 4` passed on that debug APK. The artifact parser inspected all nine packaged ARM64/x86-64 ELF libraries; all LOAD segments had minimum 16,384-byte alignment. This is static artifact inspection, not 16 KB Android runtime/device compatibility.
- Flutter analysis passed (`No issues found!`, 57.5 seconds); the full Flutter suite passed **650/650**. `node --test scripts/android-release.test.cjs scripts/check-project-memory.test.cjs` passed **16/16**. These workflow tests include synthetic candidate fixtures; they are not a GitHub Actions run or release approval.
- `flutter build web --release --no-pub` passed in 81.3 seconds. Flutter emitted wasm-dry-run incompatibilities (`dart:html`, `dart:js_util`, `package:js`) and a missing CupertinoIcons font notice; the non-Wasm web build completed. The full Flutter suite's web-responsive widget tests passed, but a Chrome-platform run failed to load because `Google\\Chrome\\Application\\chrome.exe` is absent. No Chrome or standalone Edge executable was found.
- `adb devices -l` listed no attached device.

## Evidence

The debug artifact digest above is the only local APK digest. No release-signed APK or release-candidate manifest exists. No release key/certificate, GitHub signing secret, protected environment setting, signing certificate fingerprint, release CI run, candidate upgrade, OAuth runtime, 16 KB device runtime or publication was tested.

## Limits and next action

REL-001 remains `in_progress`; `release-artifact` and `upgrade` remain unverified. Android device, browser-driven web, OAuth, live backend, 16 KB runtime, signing identity, protected environment and release authorization gates remain open. QA-001 remains open; M2 stays disabled. Nothing was published, tagged, pushed, dispatched or uploaded. Next: perform exact-candidate signing/build verification in the protected release CI environment with authorized signing identity, then run the required device upgrade/OAuth/16 KB checks after QA-001 dependencies pass. Do not treat the debug digest as a candidate artifact digest.
