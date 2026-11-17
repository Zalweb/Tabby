# QA-024 — Login page and mascot hero

```json verification-metadata
{
  "id": "VER-QA-024-LOGIN",
  "task_ids": [
    "QA-024"
  ],
  "timestamp": "2026-11-17T06:49:04.179Z",
  "tested_commit": "1c1d8373829ddd46eed1dd281a90441d129c1faf",
  "dirty_tree": true,
  "environment": "Windows / Flutter; physical Lenovo TB321FU API36 ARM64; signed normal-main v1.0.4+12; authorized USB",
  "commands": [
    "focused Flutter login/auth/mascot suite",
    "flutter test --no-pub --concurrency=2 --timeout=2m",
    "isolated pin_attempts_test.dart rerun",
    "dart analyze --fatal-infos lib test integration_test",
    "normal-main signed release build with existing public-only client config",
    "verify-android-artifact.cjs certificate/package/ZIP16KB/ELF acceptance",
    "guarded same-certificate adb install -r; exact installed APK SHA256 comparison; native visual inspection"
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
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "documentation-coverage",
      "outcome": "failed"
    }
  ]
}
```

## Expected and actual results

The supplied blinking mascot is now an illustration-sized hero, free of the compact status ring/badge. A soft mint backdrop, greeting, grounding shadow and restrained accents complement the full-body character. Tablet layout uses side-by-side hero/form columns and a 440-logical-pixel form card; phone and large-text layouts stack. Google and email actions, recovery/signup, accessible password visibility, autofill and focus borders remain usable with keyboard and 200% text. The UI edit initially preserved authentication method tokens; subsequent QA-022 event-stream callback additions remain intact; session/busy guards and repository/provider behavior are preserved. Shared mascot presentation flags default on for existing consumers.

Focused suite 54/54 passed. Final full suite 759/759 passed with concurrency 2 and a 2-minute test timeout; isolated PIN suite 6/6 passed. Analysis has no issues. The initial small 200% layout check exposed an email-divider row overflow, fixed with flexible wrapping. Initial analysis found an unused import, removed. First full run passed 754 and timed out only in the unchanged production PBKDF2 test after 30 seconds; reruns retained as above, without changing production PIN code or test assertions.

Signed APK v1.0.4+12 SHA256 3747e7d8e81599f95d5a7bc567decccd5804cb1e53cbc2716f50e830f0d62206; certificate 4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a matches the previously installed app. Nondebuggable package, ZIP16KB and native ELF checks passed. No source files changed during build or before handoff. The current dirty tree includes separately owned QA-022 authentication changes and preceding branding. It is a private device candidate, not clean-commit/public release evidence.

Installed in place over +11 on the rechecked tablet/user0 without uninstall or data clear. Original firstInstallTime preserved. Pulled installed APK digest exactly matches the candidate; launch Status: ok and process running. Owner remains signed in. Login visual QA uses isolated production-widget phone/tablet renders with an Arial substitute for unavailable Inter and actual Material Icons, not device screenshots. No logout or financial Home capture was performed. No credentials or financial operations were entered.

## Evidence

[Sanitized results](QA-024-results.json), [exact source hashes](QA-024-source-manifest.json), [task](../progress/tasks/QA-024.md). Screenshots/APKs/raw logs remain ignored/local. No private financial screenshots or credentials in repository evidence.

## Limits and next action

Native login appearance on the signed-in tablet, independent review, iOS runtime, exact-candidate 16KB runtime and real screen-reader acceptance remain unverified. Artifact alignment does not establish runtime acceptance. Existing Cupertino-font, Java native-access and package_info_plus future-KGP warnings persist. Global base coverage still flags the unrelated concurrent using-superpowers skill files and skills-lock.json without an owning task; preserve them for their owner. Current visual acceptance does not verify QA-022's live Google provider. Owner may review the updated tablet layout; independent review is required before release promotion.
