# QA-034 - Android/iOS parity and unsigned IPA preparation

```json verification-metadata
{
  "id": "VER-QA-034-IOS-PARITY",
  "task_ids": ["QA-034"],
  "timestamp": "2026-11-17T19:40:00+00:00",
  "tested_commit": "ede9e287495807bac3c26a0a131729321cb2c4b8",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; immutable accepted Android22 plus narrow iOS overlay; macOS CI not yet started",
  "commands": ["frozen flutter test --no-pub --concurrency=2 --timeout=2m", "frozen dart analyze --fatal-infos lib test integration_test", "17 focused platform/receiving tests", "7 Python config/package fixture checks", "exact publication blob/source hash and client-only config validation"],
  "checks": [
    {"category": "platform-parity", "outcome": "passed"},
    {"category": "regression", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "ios-build", "outcome": "unverified"},
    {"category": "artifact-inspection", "outcome": "unverified"},
    {"category": "integration-review", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

Parity audit completed: [matrix and sideload guide](../project/IOS_SIDELOAD.md). Exact accepted Android22 shared source/art and backend client configuration are retained. iOS QR Files/share and callback ownership are repaired; no ledger/auth/provider/API wire change. iOS remote background push and damaged-storage preserve/reset remain missing and disclosed; a passed parity-review check does not assert identical native capabilities. iOS local alarms/media/biometrics/Keychain have source adapters but lack current physical-device acceptance.

Full frozen906/906, clean analysis,17 focused platform/receiving cases and7 Python packaging/client-config fixtures pass. iOS supported-platform test failed before implementation and passes after. Initial6 const lint infos in the native smoke were corrected; first Python executable-mode check exposed Windows chmod semantics, now Runner is explicitly executable and all7 fixture checks pass. Python synthetic Apple-tool fixtures establish guard/ZIP behavior, not native build acceptance. No new physical iPhone pass or IPA exists at this checkpoint.

Candidate `codex/ios-sideload-20261118` at `f59dcd9208f89e7771fe3302adc48bd98ff12ef1` is locally prepared with428 whitelisted files,426 verified source hashes and no private signing/server credential material. It changes no main/tag/release. Public client configuration is prepared locally for a dedicated CI secret; only its hashes enter source. Remote main is old; running its existing workflow would not build the current tablet app. No source pushed or workflow dispatched yet.

## Evidence

[Task](../progress/tasks/QA-034.md), [plan](../plans/ios-sideload-and-parity.md), [source](QA-034-source-manifest.json), [results](QA-034-results.json), [native smoke](../../integration_test/ios_native_smoke_test.dart), [preparation](../../scripts/ios-prepare.py), [packaging](../../scripts/ios-package.py), [fixture checks](../../scripts/ios-build-tests.py), [workflow](../../.github/workflows/build-ios.yml). Local configs/snapshots/logs remain ignored. Flutter documents the [macOS/Xcode build requirement](https://docs.flutter.dev/deployment/ios), [plugin-owned callbacks](https://docs.flutter.dev/ui/navigation/deep-linking) and [implicit-engine method-channel registration](https://docs.flutter.dev/platform-integration/platform-channels); native implementation follows those contracts.

## Limits and next action

The GitHub repository is public. Obtain explicit approval for the concrete isolated source/build branch and client-only CI setting, then push only that prepared candidate and run macOS CI. Verify actual simulator results, unsigned device archive/bundle/arm64/art hashes and IPA digest before delivery. User selected AltStore/Sideloadly; no Apple credentials, TestFlight/App Store publication or backend deployment. Physical iPhone Google/Files/share/wallet/notification/Face ID behavior and independent review remain unverified.
