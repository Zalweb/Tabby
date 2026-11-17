# QA-034 - Android/iOS parity and unsigned IPA preparation

```json verification-metadata
{
  "id": "VER-QA-034-IOS-PARITY",
  "task_ids": ["QA-034"],
  "timestamp": "2026-11-17T21:47:29Z",
  "tested_commit": "f589540b332eacf1a7647a01d0bd72e6e0d62cff",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; exact publication commit f589540b332eacf1a7647a01d0bd72e6e0d62cff on codex/ios-sideload-20261118; GitHub macOS Intel runner CI",
  "commands": ["frozen flutter test --no-pub --concurrency=2 --timeout=2m", "frozen dart analyze --fatal-infos lib test integration_test", "17 focused platform/receiving tests", "7 Python config/package fixture checks", "exact publication blob/source hash and client-only config validation", "gh run view 44172480877 required-step check", "artifact download and local IPA inspection (qa034-download.cjs, qa034-inspect-download.py)", "independent review: ios-prepare.py --verify-source (951 hashes), ios-build-tests.py (9 checks), fresh GitHub API run confirmations, credential scan"],
  "checks": [
    {"category": "platform-parity", "outcome": "passed"},
    {"category": "regression", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "ios-build", "outcome": "passed"},
    {"category": "artifact-inspection", "outcome": "passed"},
    {"category": "integration-review", "outcome": "passed"}
  ]
}
```

## Expected and actual results

Parity audit completed: [matrix and sideload guide](../project/IOS_SIDELOAD.md). Exact accepted Android22 shared source/art and backend client configuration are retained. iOS QR Files/share and callback ownership are repaired; no ledger/auth/provider/API wire change. iOS remote background push and damaged-storage preserve/reset remain missing and disclosed; a passed parity-review check does not assert identical native capabilities. iOS local alarms/media/biometrics/Keychain have source adapters but lack current physical-device acceptance.

Full frozen906/906, clean analysis,17 focused platform/receiving cases and7 Python packaging/client-config fixtures pass. iOS supported-platform test failed before implementation and passes after. Initial6 const lint infos in the native smoke were corrected; first Python executable-mode check exposed Windows chmod semantics, now Runner is explicitly executable and all7 fixture checks pass. Python synthetic Apple-tool fixtures establish guard/ZIP behavior, not native build acceptance. No new physical iPhone pass or IPA exists at this checkpoint.

Candidate `codex/ios-sideload-20261118` at `f59dcd9208f89e7771fe3302adc48bd98ff12ef1` is locally prepared with428 whitelisted files,426 verified source hashes and no private signing/server credential material. It changes no main/tag/release. Public client configuration is prepared locally for a dedicated CI secret; only its hashes enter source. Remote main is old; running its existing workflow would not build the current tablet app. No source pushed or workflow dispatched yet.

2026-11-17T21:40:20Z - Final CI run `44172480877` at `f589540b332eacf1a7647a01d0bd72e6e0d62cff` passed source/CocoaPods/locked-package/client-config/regression checks, the constrained native-evidence reuse gate (run `44167297902`, 3/3 named cases, 231 exact input hashes; simulator steps skipped because inputs matched), unsigned archive, IPA packaging and upload in 12m59s. Downloaded artifact `14370265229` (`Tabby-ios-sideload-20`) and inspected the genuine device IPA locally: `Tabby-1.0.4+23`, bundle `com.zalweb.tabby`, minimum iOS 15.0, arm64 Mach-O executable, ZIP CRC passed, 24 branding assets verified, no private signing material; IPA 31,633,697 bytes, sha256 `0c0cea8eae1032eca5f4782a5eddc4cdddb4dafe9043d553eba21d2c0efcb8d6`. Physical iPhone acceptance and independent integration review remain unverified; this continuation ran via Qoder CLI while the Codex session was quota-blocked, and no runtime source changed beyond the already-pushed f589540.

## Independent integration review

2026-11-17T21:47:29Z - Qoder CLI reviewed the published candidate independently of the Codex authoring session. Scope: the QA-034 overlay between recorded base `2741f7c3c9d97701226b0f4eb2df329ccd6ec043` and artifact source `f589540b332eacf1a7647a01d0bd72e6e0d62cff` (59 changed paths; substantive changes in `build-ios.yml`, `build-mobile.yml`, `AppDelegate.swift`, `Info.plist`, Podfile/project deployment target, five iOS scripts, the native smoke test, the QR-export platform guard and four test files; the remainder is Flutter template/asset churn). Unrelated shared work uploaded in the same all-work commit, such as receipt-format repairs, was excluded and remains owned by its own task records.

Method and fresh evidence: read every substantive change; re-ran `scripts/ios-prepare.py --verify-source` in the publication checkout (951 frozen hashes verified) and `scripts/ios-build-tests.py` (9 fixture checks pass); confirmed run `44172480877` at `f589540` directly through the GitHub API (all required steps success, simulator steps intentionally skipped by the reuse gate); confirmed run `44167297902` at `5bea03d` had the actual simulator step success and failed only at the later packaging stage; cross-checked the downloaded IPA sha256 against its sidecar; scanned the published tree for credential patterns (none; only synthetic guard fixtures). The workflow removes the earlier `flutter create`, `flutter_launcher_icons` and `.env`-from-secrets steps; injects public client configuration only into a mode-600 file outside the source tree; and enforces an unsigned arm64 payload with a private-material scan and 24 verified branding-asset hashes. The QR export channel accepts PNG bytes only and cannot confirm payments; no ledger or money code is touched by this overlay.

Outcome: passed, no blocking findings. Residual risks recorded: (1) there is no `ios/Podfile.lock`, so `pod install --repo-update` resolves pod versions at build time - the delivered IPA is verified, but rebuilds may resolve different pod patch versions; commit the lockfile when convenient; (2) the native smoke test verifies channel capabilities and malformed-input rejection but does not automate the Files/share UI completions; (3) Keychain coverage is indirect through the encrypted-cache reopen path rather than direct SecItem assertions; (4) the constrained reuse gate trusts the repo-owned source manifest and applies only to unchanged native inputs (231 hashes).

## Evidence

[Task](../progress/tasks/QA-034.md), [plan](../plans/ios-sideload-and-parity.md), [source](QA-034-source-manifest.json), [results](QA-034-results.json), [native smoke](../../integration_test/ios_native_smoke_test.dart), [preparation](../../scripts/ios-prepare.py), [packaging](../../scripts/ios-package.py), [fixture checks](../../scripts/ios-build-tests.py), [workflow](../../.github/workflows/build-ios.yml). Local configs/snapshots/logs remain ignored. Flutter documents the [macOS/Xcode build requirement](https://docs.flutter.dev/deployment/ios), [plugin-owned callbacks](https://docs.flutter.dev/ui/navigation/deep-linking) and [implicit-engine method-channel registration](https://docs.flutter.dev/platform-integration/platform-channels); native implementation follows those contracts.

## Limits and next action

The GitHub repository is public. The concrete isolated branch was approved and pushed; macOS CI produced and uploaded the unsigned device IPA, which was downloaded and inspected as recorded above, and the independent integration review passed on 2026-11-17T21:47:29Z. Deliver the inspected IPA for user signing via AltStore/Sideloadly and verify physical iPhone Google/Files/share/wallet/notification/Face ID behavior; no Apple credentials, TestFlight/App Store publication or backend deployment. The reused-native-evidence gate covers only unchanged native app inputs; any input change reruns simulator checks. Decide whether to commit an `ios/Podfile.lock` before the next rebuild so pod versions are reproducible.
