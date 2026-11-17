# VER-QA-002 — USB automation source and initial physical attempt

```json verification-metadata
{
  "id": "VER-QA-002-USB-AUTOMATION",
  "task_ids": ["QA-002"],
  "timestamp": "2026-11-13T05:04:00+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows PowerShell; Node26.13; Flutter3.47.8/Dart3.13.7; Android SDK36 and ADB37.0.1. Physical Lenovo TB321FU/API36 with 4096-byte pages initially attached by USB; device disconnected after isolated seed installation. Concurrent AZ-001 work is outside this evidence.",
  "commands": [
    "node --test scripts/usb-test.test.cjs scripts/android-release.test.cjs scripts/check-project-memory.test.cjs",
    "node scripts/usb-test.cjs --suite smoke",
    "node scripts/usb-test.cjs --suite preflight",
    "flutter analyze --no-pub",
    "dart analyze integration_test/usb_seed_test.dart integration_test/usb_smoke_test.dart integration_test/usb_live_test.dart",
    "flutter test --no-pub",
    "flutter build apk --debug --no-pub --target=integration_test/usb_smoke_test.dart --dart-define=TABBY_USB_TEST=true",
    "flutter build apk --debug --no-pub --target=integration_test/usb_live_test.dart --dart-define=TABBY_USB_TEST=true",
    "aapt dump badging build/app/outputs/flutter-apk/app-debug.apk",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0",
    "git diff --check"
  ],
  "checks": [
    {"category": "automation-regression", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "flutter-regression", "outcome": "passed"},
    {"category": "android-test-build", "outcome": "passed"},
    {"category": "usb-device", "outcome": "failed"},
    {"category": "live-backend", "outcome": "unverified"},
    {"category": "migration-rehearsal", "outcome": "unverified"},
    {"category": "integration-review", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

The runner's four safety regressions passed: reject wireless/emulator/invalid selection, reject a production-package APK, require explicit HTTPS/client-key/fixture setup and reject invalid suites/repetition. The combined Node suite passed 20/20. Dart scoped analysis and Flutter analysis passed. Initial Flutter full suite failed the static production applicationId assertion after the first test-isolation implementation; Gradle was revised to retain the production applicationId and use a debug-only suffix. The callback configuration test was updated for separately resolved production/test schemes. The superseding full Flutter run passed 651/651.

Seed, smoke and live test APKs compiled. Artifact badging reported package `com.zalweb.tabby.usbtest`, version1.0.4+5, minSDK24/target36. Production package inventory was present before installation. The runner installed only the verified seed APK and granted notifications only to the test package. It then failed before test execution: Flutter's USB-serial launch reported `device not found`, and subsequent `adb -d get-serialno` returned `no devices found`. This is a failed physical run, not a native acceptance pass. Follow-up preflight also failed and wrote a failed report. No wireless ADB connection, production uninstall or package-data clearing was issued.

## Evidence

Repository sources (currently uncommitted): [runner](../../scripts/usb-test.cjs), [safety tests](../../scripts/usb-test.test.cjs), [usage](../project/USB_TESTING.md), [migration preparation](../project/AZURE_MIGRATION.md). The local ignored smoke report is `.dart_tool/usb-tests/2026-11-12T20-53-50-564Z/report.json`; its build/install steps passed and drive step failed. The subsequent ignored preflight report is `.dart_tool/usb-tests/2026-11-12T20-58-42-952Z/report.json`. Final full Flutter output is ignored `.dart_tool/usb-regression.log` (651 passed). No credentials, private media, real-user API responses or device-wide logs were collected. SDK/process sandbox denials were rerun through approved command escalation; they are not app failures.

## Limits and next action

Reconnect and authorize the physical tablet, then rerun smoke/matrix. Pending reminder probes in the existing matrix do not verify delivery. Live tests were compiled without credentials and never executed against any backend. Azure was not provisioned or accessed; production remains unchanged. Obtain current source inventory, Azure target/access/cost/lifetime and HTTPS/provider configuration, resolve concurrent Azure scope, then rehearse restore and supply a synthetic fixture account before live testing. No QA-001/REL-001 or M2 gate is closed; independent review remains open.

### 2026-11-13T05:10:45+08:00 — USB retry and Azure tooling preparation

The tablet reappeared with the same USB serial, but the runner's device-model query timed out after 60 seconds before build/install. Both SDK and WinGet ADB shell queries then stalled. A USB-only reconnect closed those shells and enumeration became empty; no wireless command or reboot was used. The ignored retry report is `.dart_tool/usb-tests/2026-11-12T21-06-46-137Z/report.json`. Source reporting now marks command timeouts explicitly; runner safety tests passed 4/4 again. Physical execution remains failed/open. The user supplied a target Azure identifier; official CLI ZIP preparation is local-only and does not establish sign-in, subscription access or deployment.

### 2026-11-13T05:13:30+08:00 — Local Azure CLI ready, sign-in handed to user

The [official Windows ZIP distribution](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows) was extracted under ignored `.dart_tool/azure-cli/sdk`. `az version` reported CLI/core2.92.0. The read-only `az account show --subscription <supplied-id>` failed because this machine was not signed in. Microsoft's device-code authentication was started and handed to the user; its code and any tokens are excluded from evidence. Subscription/credit/resource inventory is still unverified. No Azure resource, role assignment, secret, deployment, migration or billing change was made. USB subsequently enumerated an offline transport without a serial; reconnecting with a reliable data cable and authorizing debugging remain necessary.

### 2026-11-13T05:16:10+08:00 — Sign-in persistence recovery

After the user's initial completion message, `az account show` still requested login, `az account list` returned an empty list, and the prior unified-tool sign-in session was no longer available. No successful authentication is inferred from the browser step. A hidden PowerShell helper now runs the official CLI device flow outside the transient tool session; its waiting process was confirmed alive across calls. Local sign-in logs/state are ignored and contain no material committed to Git. A fresh code was given to the user. Azure access remains unverified until the exact target account query succeeds; no resource operation occurred.
