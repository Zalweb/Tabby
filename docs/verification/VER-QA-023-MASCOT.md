# QA-023 — Mascot, launcher icon and in-place tablet update

```json verification-metadata
{
  "id": "VER-QA-023-MASCOT",
  "task_ids": ["QA-023"],
  "timestamp": "2026-11-17T11:23:26+08:00",
  "tested_commit": "1c1d8373829ddd46eed1dd281a90441d129c1faf",
  "dirty_tree": true,
  "environment": "Windows; Flutter/Dart SDK already installed; signed normal-main Android 1.0.4+11; physical Lenovo TB321FU / API36 / ARM64 / primary user; authorized USB",
  "commands": [
    "adb devices -l; explicit device shell echo, hardware serial and current-user checks before implementation",
    "flutter test --no-pub test/features/tabby_mascot_sprite_test.dart test/features/tabby_mascot_animation_test.dart test/features/appearance_preferences_test.dart",
    "flutter test --no-pub",
    "dart analyze --fatal-infos lib test integration_test",
    "installed flutter_launcher_icons 0.13.1 generator with workspace configuration; preserve native 12dp adaptive foreground inset",
    "flutter build apk --release --build-number=11 --target=lib/main.dart --dart-define-from-file=<existing ignored public-only client config>",
    "node scripts/verify-android-artifact.cjs --apk <retained signed APK> --expected-cert <same installed production certificate> --commit 1c1d8373829ddd46eed1dd281a90441d129c1faf",
    "guarded adb install -r; installed version and original firstInstallTime checks; pull installed base APK and compare SHA256",
    "adb activity launch with Status: ok; read-only screenshots of empty sign-in screen show open and partially closed eyes",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs --base 1c1d8373829ddd46eed1dd281a90441d129c1faf"
  ],
  "checks": [
    {"category": "regression", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "release-artifact", "outcome": "passed"},
    {"category": "android-device", "outcome": "passed"},
    {"category": "documentation-coverage", "outcome": "failed"},
    {"category": "integration-review", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

ADB was checked first and functional. User-supplied 1254-square transparent sheet is bundled unchanged. Equal-size measured source rectangles normalize gutters and align the paw baseline. The sprite holds its first open-eye pose for 3.2 seconds, plays the eight poses over a 3.8-second total cycle, and retains existing body motion, tap behavior, messages and status badges. Sleep keeps closed eyes. Reduced motion, hidden-route TickerMode and background lifecycle stop the sprite timer; resume starts with an open-eye hold. Actual asset decoding/rendering at 64/128 pixels, all eight timeline positions, looping, interruption, route hiding, lifecycle and sleeping/waking pass new widget checks.

Focused mascot/appearance suite: **37/37 passed**. Full Flutter regression suite: **749/749 passed**. Full Dart analysis over lib/test/integration_test: **no issues**. Launcher generation succeeded for Android, iOS and web. Foreground has real alpha; opaque counterpart has no transparency. Android adds a 12dp native inset to preserve ears/paws inside launcher masks. Exact prompts and saved asset paths are in [generation provenance](../assets/mascot-launcher-prompts.md).

Signed normal-main **1.0.4+11**, package com.zalweb.tabby, APK SHA256 **8e6d959f734029a1627681b5075cbe74670c53875f172754245c2060e2a9401f**. Certificate SHA256 **4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a**, matching installed v1.0.4+10. Nondebuggable package, signature, ZIP16KB and native ELF alignment checks passed. Source hashes were identical before and after the successful build. Build includes the existing unrelated QA-022 working-tree changes; this is explicitly a dirty-tree private candidate, not a clean commit or public release.

Guarded in-place installation succeeded on the rechecked physical tablet/primary user. Original firstInstallTime is preserved; no uninstall or data clear occurred. Installed base APK was pulled and exactly matches the verified SHA256. Activity launch returned Status: ok and process remained running. Visually inspected the actual native sign-in screen: full-body mascot fits its ring, ears/tail/paws are visible, and captured open/partially closed eyes demonstrate native blink playback. No login credentials, sample financial records or account actions were entered. App remains open at sign-in.

## Evidence

[Sanitized results](QA-023-results.json), [exact build source hashes](QA-023-source-manifest.json), [task](../progress/tasks/QA-023.md). Raw screenshots, APKs and build logs remain ignored/local; screenshots are not shared repository evidence. No real user financial data was captured.

Failure history retained: first test attempt had two incorrect awaits on a void lifecycle API; corrected. Next screenshot check waited for raster work inside fake time; cancelled and corrected using runAsync. Final focused/full suites passed. Analyzer initially flagged deprecated TickerMode.of; corrected to the installed SDK's valuesOf API. First release attempt with --no-pub failed because stale generated registration referenced the integration-test plugin; normal Flutter build refreshed generated metadata and passed. Existing Cupertino font, Java native-access and package_info_plus future-KGP warnings remain; they did not fail the accepted build. Sandbox cache/subprocess denials were rerun with required approved access.

## Limits and next action

Independent integration review, iOS runtime and a fresh 16KB-device run for this exact candidate remain unverified. Native artifact alignment is distinct from runtime acceptance. No backend/provider or public release work belongs to this task. Current QA-022 Google sign-in work remains separately owned and is not declared verified by these visual checks. Owner may continue normal tablet use; review the implementation before promoting this private candidate to any release process.

2026-11-17T11:30:56+08:00 — Documentation refresh/plain validation pass (77 tasks, 45 findings, 98 verification records), and Git whitespace validation passes. Full base coverage fails for the unrelated concurrent .agents/skills/using-superpowers installation and skills-lock.json because those additions lack an updated owning task. No QA-023 application/artwork path is reported uncovered. Preserve that work; its owner must record coverage before the global check can pass. The evidence helper's initial UTF-8 read of a PowerShell UTF-16 log was corrected; referenced JSON files now exist and plain validation passes. Final Git status inspected; no staging/commit or unrelated cleanup.
