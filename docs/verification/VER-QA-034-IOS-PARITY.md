# QA-034 - Android/iOS parity and unsigned IPA preparation

```json verification-metadata
{
  "id": "VER-QA-034-IOS-PARITY",
  "task_ids": ["QA-034"],
  "timestamp": "2026-11-17T22:50:00Z",
  "tested_commit": "70ab9f393f359b1e99a439b5a8c509a1da761871",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; published source f589540b332eacf1a7647a01d0bd72e6e0d62cff and lock commit70ab9f393f359b1e99a439b5a8c509a1da761871 on codex/ios-sideload-20261118; committed CocoaPods lock1.17.0 with40 pods verified by GitHub macOS Intel runs44184965803/44188415197",
  "commands": ["frozen flutter test --no-pub --concurrency=2 --timeout=2m", "frozen dart analyze --fatal-infos lib test integration_test", "17 focused platform/receiving tests", "7 Python config/package fixture checks", "exact publication blob/source hash and client-only config validation", "gh run view 44172480877 required-step check", "artifact download and local IPA inspection (qa034-download.cjs, qa034-inspect-download.py)", "independent review: ios-prepare.py --verify-source (951 hashes), ios-build-tests.py (9 checks), fresh GitHub API run confirmations, credential scan", "qa034-lock-verify.cjs mode a: artifact14375836506 Podfile.lock, PODFILE CHECKSUM equals sha1(ios/Podfile), CocoaPods1.17.0/40 pods, no CRLF", "qa034-lock-verify.cjs mode b: artifact14377496912 lock byte-identical to committed70ab9f3 lock, fresh simulator3 named cases passed, pinned Flutter revision737ba8f885dc774b53b442759999a312c9461e4e, IPA sidecar sha256 match"],
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

Outcome: passed, no blocking findings. Residual risks recorded: (1) there is no `ios/Podfile.lock`, so `pod install --repo-update` resolves pod versions at build time - the delivered IPA is verified, but rebuilds may resolve different pod patch versions; commit the lockfile when convenient; (2) the native smoke test verifies channel capabilities and malformed-input rejection but does not automate the Files/share UI completions; (3) Keychain coverage is indirect through the encrypted-cache reopen path rather than direct SecItem assertions; (4) the constrained reuse gate trusts the repo-owned source manifest and applies only to unchanged native inputs (231 hashes). Residual risk (1) was resolved on 2026-11-17 by the committed lockfile recorded below; risks (2)-(4) stand.

## CocoaPods lockfile reproducibility

2026-11-17T22:50:00Z - User asked to pin the iOS dependency graph. Workflow commit `0bdccde7d84f4d3b022583a53633bf779d1ea5d9` added a "Record resolved CocoaPods lock" step that copies `ios/Podfile.lock` into the uploaded artifact, plus an `Install native dependencies` check that fails `pod install` if it would rewrite the lock once tracked. Run `44184965803` (`0bdccde`, 18m14s) generated the lock with the pinned Flutter 3.47.8 on the macOS Intel runner: CocoaPods `1.17.0`, 40 pod entries, 5,249 bytes, sha256 `813b9eb09557fa3ac34e696064303b5e1be3c5af06a6d2f52f5854720108c03f`; `PODFILE CHECKSUM` `5bfdf9108c6226ec630101f571d0557d7585e921` equals the SHA1 of the committed `ios/Podfile`; its archived IPA was sha256 `b51b4d003d4531238c47dcc3702e03bf5cf20ceecc5980b3b3e986fb3c60f66d` (31,633,695 bytes).

Lock commit `70ab9f393f359b1e99a439b5a8c509a1da761871` adds the artifact lock byte-for-byte and refreshes the frozen manifest (952 files). Run `44188415197` (`70ab9f3`, 26m42s) proved the pin end-to-end: `pod install --repo-update` reproduced the committed lock with no `git diff` drift; the native-evidence reuse gate correctly refused reuse because native inputs changed and ran all three named simulator cases fresh (pass, pinned revision `737ba8f885dc774b53b442759999a312c9461e4e`); the uploaded artifact lock is byte-identical to the committed lock; the unsigned IPA is sha256 `cadb1bc6522f681263b50894c073d1b98ccf08704d2ff686d818acaed24196fe` (31,633,694 bytes) with a matching sidecar. `qa034-lock-verify.cjs` modes a/b re-checked the checksum/Podfile SHA1, committed-lock byte equality, 3/3 fresh native cases and the IPA sidecar locally.

## Evidence

[Task](../progress/tasks/QA-034.md), [plan](../plans/ios-sideload-and-parity.md), [source](QA-034-source-manifest.json), [results](QA-034-results.json), [native smoke](../../integration_test/ios_native_smoke_test.dart), [preparation](../../scripts/ios-prepare.py), [packaging](../../scripts/ios-package.py), [fixture checks](../../scripts/ios-build-tests.py), [workflow](../../.github/workflows/build-ios.yml). Local configs/snapshots/logs remain ignored. Flutter documents the [macOS/Xcode build requirement](https://docs.flutter.dev/deployment/ios), [plugin-owned callbacks](https://docs.flutter.dev/ui/navigation/deep-linking) and [implicit-engine method-channel registration](https://docs.flutter.dev/platform-integration/platform-channels); native implementation follows those contracts.

## Limits and next action

The GitHub repository is public. The concrete isolated branch was approved and pushed; macOS CI produced and uploaded the unsigned device IPA, which was downloaded and inspected as recorded above, and the independent integration review passed on 2026-11-17T21:47:29Z. Deliver the inspected IPA for user signing via AltStore/Sideloadly and verify physical iPhone Google/Files/share/wallet/notification/Face ID behavior; no Apple credentials, TestFlight/App Store publication or backend deployment. The reused-native-evidence gate covers only unchanged native app inputs; any input change reruns simulator checks. `ios/Podfile.lock` is now committed and CI rejects pod-resolution drift (see the lockfile section above), so rebuilds from the same commit reproduce the reviewed pod versions.
