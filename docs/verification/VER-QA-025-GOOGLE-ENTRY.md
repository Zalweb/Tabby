# QA-025 — Google-only welcome and introduction

```json verification-metadata
{
  "id": "VER-QA-025-GOOGLE-ENTRY",
  "task_ids": [
    "QA-025"
  ],
  "timestamp": "2026-11-17T07:49:02.066Z",
  "tested_commit": "f8b731463e2dd0efd5f160f82f093fa0c26da1e4",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; physical Lenovo TB321FU API36 ARM64 4KB; signed main1.0.4+13; existing Azure Auth",
  "commands": [
    "flutter test --no-pub --concurrency=2 --timeout=2m",
    "dart analyze --fatal-infos lib test integration_test",
    "node --test scripts/usb-test.test.cjs",
    "python -m unittest discover -s deploy/azure-full -p test_google*.py",
    "node scripts/usb-test.cjs --suite entry",
    "signed release ARM64 build13 with six public Firebase/Supabase client defines",
    "node scripts/verify-android-artifact.cjs with expected production certificate",
    "guarded adb install -r; pull installed APK and compare SHA256; launch",
    "reviewed Auth-only Google registration operator via Azure RunCommand; independent public settings/authorize probe"
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
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "server-provider-config",
      "outcome": "passed"
    },
    {
      "category": "google-registration",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "project-memory",
      "outcome": "passed"
    },
    {
      "category": "documentation-coverage",
      "outcome": "failed"
    }
  ]
}
```

## Expected and actual results

Normal entry offers only Continue with Google. A large newly generated Tabby sits on a cream/amber welcome. The post-Google registration check uses the real account profile: completed profiles go home; unfinished profiles see three minimal introduction screens then required name/Philippine mobile and optional receiving methods. An encrypted account-specific acknowledgment resumes interrupted setup without repeating the introduction. Unknown profile results offer retry and cannot unlock Home. Current-session/generation checks reject stale results after account switches, signout and same-account relogin. Existing callback/error/cancellation protections remain. Legacy recovery deep links remain compatible, without normal recovery/password links.

All776 host Flutter tests pass; analysis has no issues.83 focused tests,3 routing tests,10 USB-runner guards and9 Google operator/callback Python tests pass. Production-widget preview fixture passes and phone/tablet/light/dark renders were inspected. Cases include small/landscape/200% text, intro navigation/storage failures and stale sessions. Initial broad failures were obsolete email/pre-login expectations; updated assertions pass in the full run. Earlier profile test taps needed ensureVisible after the larger mascot moved the control below the viewport.

Actual physical entry suite passes all3 required cases in separate com.zalweb.tabby.entrytest: Google-only UI/art, intro Back/Next/Skip with real encrypted storage, and profile-check retry. Synthetic actor/profile responses do not establish a live new-user OAuth journey. The isolated entry package was removed afterward; main and concurrent FCM fixture preserved.

Reviewed Auth-only deployment google-registration-20261117T073155Z-d40bbe passed encrypted backup readback/decryption, service health and policy persistence. Existing Google credentials/callback/users/financial records were preserved. Registration enabled with Google as the sole provider; email/password/signup, phone and anonymous probes return provider-disabled errors. Independent public settings200 and Google authorize302 to accounts.google.com passed. No user account created by probes. Operator SHA256 504518119c73e0fea7236f9b673a2e61feb45bcb28e8b960e902a8712e7d27f2. Future callback/application configuration honors this persisted provider policy.

Private signed main1.0.4+13 built successfully with reviewed public-only Firebase identifiers plus existing Azure client settings. Source hashes stayed unchanged during build and at handoff. APK SHA256 a7e260f3674572cbc51adc4a31e105d52919b77012df3590a90208f9f291adb9; certificate 4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a; nondebuggable package/ZIP16KB/native ELF checks pass. Guarded same-key install -r upgraded12→13 without clearing data or signing out. Original firstInstallTime retained; pulled installed APK bytes match exactly; native launch Status: ok and process running. Owner stayed signed in; no financial Home screenshot or owner financial actions performed.

## Evidence

[Sanitized results](QA-025-results.json), [exact candidate source hashes](QA-025-source-manifest.json), [task](../progress/tasks/QA-025.md), [design/implementation plan](../plans/google-entry-introduction.md), [generated artwork and exact prompts](../assets/google-welcome-prompts.md), [native case contract](../../integration_test/android_google_entry_cases.json). Raw local logs/APKs/previews remain ignored. Build is from a dirty tree that includes earlier branding and concurrent Firebase work; this is not clean-commit release evidence.

## Limits and next action

Real creation/consent with a new Google identity and its complete introduction→saved-profile→Home journey remain unverified. Existing-account Google success is historical QA-022 evidence, not new-user acceptance. Independent integration review, iOS runtime, actual screen-reader acceptance and exact-candidate16KB runtime remain unverified; alignment is not runtime acceptance. Existing Cupertino-font, Java native-access and package_info_plus future-KGP warnings persist. Global documentation coverage of unrelated skill/reference inputs needs their owner; preserve that work. Task stays implemented pending the required fresh-account acceptance and review. No public release performed.


2026-11-17T07:50:29.328Z — Final handoff checks: memory refresh/plain validation pass (79 tasks,45 audit findings,102 evidence records); Git diff --check passes. Base coverage fails only eight existing using-superpowers skill files, skills-lock.json and15 supplied reference JPEGs; no implementation file uncovered. Existing changes preserved without committing other owners' work. All198 candidate source hashes still match.
