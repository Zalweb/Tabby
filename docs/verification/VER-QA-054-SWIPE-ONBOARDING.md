# VER-QA-054 — Swipeable first-launch tour

```json verification-metadata
{
  "id": "VER-QA-054-SWIPE-ONBOARDING",
  "task_ids": ["QA-054"],
  "timestamp": "2026-11-19T17:03:25+08:00",
  "tested_commit": "a7394bdfb5bdae53c8a24bec6f1d8addd32abae9",
  "dirty_tree": true,
  "apk_sha256": "6ee677fb9e5fcbfe4209d88965fd498890f2dc65c08069de05d76e5ba31ade72",
  "certificate_sha256": "4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a",
  "environment": "Windows Flutter host, dedicated Android API 36 x86_64 emulator with 16 KB pages, physical Lenovo TB321FU tablet over USB",
  "commands": [
    "flutter test --no-pub --reporter expanded for auth_onboarding_test, login_layout_test, startup_gate_test, registration_flow_test, and registration_routing_test on the scoped branch",
    "flutter test --no-pub --concurrency=1 --reporter expanded for the same five files and reference_navigation_layout_test on the integrated working tree",
    "dart analyze --fatal-infos on the three modified Dart files",
    "flutter build apk --release --target-platform=android-arm64,android-x64 --build-name=1.0.4 --build-number=41 with preserved Firebase client configuration",
    "node scripts/verify-android-artifact.cjs with the existing release certificate",
    "ADB swipe, Back key, accessibility-tree inspection, sign-in entry and cold relaunch on the dedicated emulator",
    "adb install -r, installed APK readback, UID and first-install checks, am start -W, and resumed activity on the tablet"
  ],
  "checks": [
    {"category": "regression", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "release-artifact", "outcome": "passed"},
    {"category": "android-device", "outcome": "passed"},
    {"category": "upgrade", "outcome": "passed"},
    {"category": "ios-device", "outcome": "unverified"},
    {"category": "public-release", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

The scoped review passed 42 Flutter tests and Dart analysis. The current working tree passed 57 focused tests, including combined navigation and first-launch coverage. Widget tests checked movement before the finger lifts, forward and reverse settlement, a cancelled Next animation, light and dark contrast, 200% text in short viewports, screen-reader announcement, and the existing Google entry rules.

On the signed APK in the dedicated fresh emulator, swipes worked both ways across all three pages. The dark active marker measured 26 pixels at rest and 70 pixels mid-drag in native screenshots. The button bounds were stable. Next and Android Back moved between slides. Get started opened the Google-only welcome, and a cold relaunch preserved the completed tour. No Google credentials were entered.

## Evidence

The signed APK is `com.zalweb.tabby` `1.0.4+41`. The verified QA-053 build 40 inputs were frozen. The manifest comparison found only the onboarding view changed among 388 inputs. Signature, non-debuggable package, 16 KB ZIP and native ELF alignment, and the existing Firebase client resources passed. The physical tablet upgraded from 40 to 41 in place. The package UID and first install time were retained, installed APK bytes matched the verified SHA-256, and MainActivity resumed. The inspected screenshots and signed build records remain in local ignored storage.

## Limits and next action

The fresh interaction was tested in the dedicated emulator. Physical verification covered the signed in-place upgrade and launch with the existing tablet data. The reviewed source is on [the onboarding branch](https://github.com/Zalweb/Tabby/tree/codex/qa054-swipe-onboarding). Main integration, physical iOS verification and public release remain open.
