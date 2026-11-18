# VER-REL-002 — Production rebind artifact verification

```json verification-metadata
{
  "id": "VER-REL-002-PROD-REBIND",
  "task_ids": ["REL-002"],
  "timestamp": "2026-11-18T17:47:00+08:00",
  "tested_commit": "a7394bdfb5bdae53c8a24bec6f1d8addd32abae9",
  "dirty_tree": true,
  "environment": "Windows 10.0.26300 (Qoder CLI); Flutter 3.47.8 stable at C:/src/flutter; Android build-tools 36.0.0 with Android Studio JBR; GitHub Actions macos-15-intel run 44274221017 on branch codex/ios-prod-20261118 (iOS source commit 921e22779fad45144be16fad265dcd7643122aee). The Android build used the shared working tree at HEAD plus preserved concurrent uncommitted changes; the iOS build used the pushed branch commit.",
  "commands": [
    "curl -fsS -H \"apikey: <publishable key>\" https://ziaqrkagsvozhotremsx.supabase.co/auth/v1/health",
    "curl -fsS -H \"apikey: <publishable key>\" https://ziaqrkagsvozhotremsx.supabase.co/auth/v1/settings",
    "curl -sS -o /dev/null -D - \"https://ziaqrkagsvozhotremsx.supabase.co/auth/v1/authorize?provider=google&redirect_to=io.supabase.tabby://login-callback\"",
    "curl -fsS -H \"apikey: <publishable key>\" \"https://ziaqrkagsvozhotremsx.supabase.co/rest/v1/users?select=id&limit=1\"",
    "flutter build apk --release --target-platform=android-arm64,android-x64 --build-number=24 --target=lib/main.dart --dart-define-from-file=.dart_tool/readiness/qa041-prod-public-client.json",
    "aapt dump badging .dart_tool/readiness/qa041-release24.apk",
    "apksigner verify --print-certs --verbose .dart_tool/readiness/qa041-release24.apk",
    "zipalign -c -P 16 4 .dart_tool/readiness/qa041-release24.apk",
    "python ELF PT_LOAD alignment check over lib/arm64-v8a/libapp.so and lib/x86_64/libapp.so",
    "unzip -p <apk> lib/<abi>/libapp.so | grep -a -c ziaqrkagsvozhotremsx.supabase.co",
    "flutter test --no-pub",
    "flutter analyze --no-pub lib",
    "python scripts/ios-prepare.py --verify-source",
    "gh workflow run build-ios.yml --repo Zalweb/Tabby --ref codex/ios-prod-20261118 -f build_number=24",
    "gh run download 44274221017 -n Tabby-ios-sideload-23",
    "unzip -t Tabby-1.0.4+24-unsigned.ipa; python plistlib inspection of Payload/Runner.app/Info.plist; sha256sum"
  ],
  "checks": [
    {"category": "release-artifact", "outcome": "passed"},
    {"category": "regression", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "oauth", "outcome": "unverified"},
    {"category": "upgrade", "outcome": "unverified"},
    {"category": "device-ui-regression", "outcome": "unverified"},
    {"category": "integration-review", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

Production probes: `/auth/v1/health` returned GoTrue `v2.198.0`; `/auth/v1/settings` returned `google: true` with the other external providers disabled; `/auth/v1/authorize?provider=google&redirect_to=io.supabase.tabby://login-callback` returned HTTP 302 to `accounts.google.com` with client ID `137141086000-p2o6c1hminjif8i5f739n3a6ils7ucmm` and callback `https://ziaqrkagsvozhotremsx.supabase.co/auth/v1/callback`; `/rest/v1/users?select=id&limit=1` returned `[]`. Both auth endpoints required the publishable-key header; without it they returned 401.

Android: the release build completed. The APK is 73,609,244 bytes with SHA-256 `006c2cff0b7b474c24f93437c80886575d700def2505b11db9ef724c548a0e77`, package `com.zalweb.tabby`, version `1.0.4` (24). `apksigner` verified the v2 scheme with one signer, certificate SHA-256 `4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a` (identical to the accepted v23 key). `zipalign -c -P 16 4` passed and every `PT_LOAD` segment in both ABI libraries is aligned at 65536. The production origin occurs in both `libapp.so` files and `cloudapp.azure` occurs zero times. The package is not debuggable.

Regression: `flutter test --no-pub` reported `All tests passed!` with 1152 tests; `flutter analyze --no-pub lib` reported `No issues found!` in 62.1 s on the same tree.

iOS: `python scripts/ios-prepare.py --verify-source` verified all 952 frozen source hashes on `921e227`, and the four pinned client-config SHA-256 values match the production URL, publishable key and unchanged Google iOS/Web client IDs. In CI run 44274221017 the source verification, locked packages, client-config hash enforcement, CocoaPods install, platform regression tests, simulator boot and the native channel/Keychain/encryption/image smoke test passed; the unsigned archive was built and packaged. The downloaded IPA is 31,633,412 bytes with SHA-256 `c5558cd46ff03e8cdbc247027a6ec284347218eb56144f3f3d8bc06b24ea033b` (matching the CI packaging manifest), bundle `com.zalweb.tabby`, version 1.0.4 (24), minimum iOS 15.0, arm64, unsigned with no embedded provisioning profile or `_CodeSignature`, ZIP CRC clean, 24 branding assets verified, with the production origin embedded (7 occurrences in the Dart AOT snapshot) and no Azure origin. The packaging manifest records `source_commit 921e22779fad45144be16fad265dcd7643122aee`, `unsigned: true` and `physical_iphone_verified: false`.

## Evidence

GitHub Actions run 44274221017 artifact `Tabby-ios-sideload-23`, downloaded and inspected locally; committed iOS source `921e227` on branch `codex/ios-prod-20261118`; Android artifact `.dart_tool/readiness/qa041-release24.apk` (git-ignored local build output). Publication is GitHub release `v1.0.4+24` at `https://github.com/Zalweb/Tabby/releases/tag/v1.0.4%2B24`, with canonical `Tabby.apk`, `Tabby.ipa` and versioned copies. The Android source tree was not clean: `dirty_tree` is recorded as true, and this evidence does not claim an exact committed Android candidate.

## Limits and next action

No physical Android device or iPhone was used after the rebind, so Google sign-in on the production origin, upgrade over the installed v23 build, and Sideloadly signing/launch remain unverified. The shared Android working tree was not frozen, so the test/analyzer runs shortly after the build are not proven bit-identical to the APK build inputs, and the recorded `dirty_tree: true` bars any exact-candidate claim. The official candidate contract is not met: no `docs/releases/<commit>.json` record, REL-001/QA-001 and the required device/OAuth/16 KB runtime and independent review gates remain open. Next: install both builds on real devices, sign in with Google, confirm Home loads against managed production, and record the runtime results; then decide Azure VM disposal and official candidate production.
