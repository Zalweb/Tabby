# VER-QA-012-ANDROID-SESSIONS

```json verification-metadata
{
  "id": "VER-QA-012-ANDROID-SESSIONS",
  "task_ids": [
    "QA-012"
  ],
  "timestamp": "2026-11-14T03:06:06+08:00",
  "tested_commit": "0b03f828655408d99bf51e80395de241ec25f295",
  "dirty_tree": true,
  "environment": "Physical Lenovo TB321FU/API36/4096-byte pages; synthetic account/provider/clipboard ports and device-loopback HTTP; Flutter3.47.8/Dart3.13.7",
  "commands": [
    "node scripts/usb-test.cjs --suite sessions --transport wifi --device <advertised-connection-endpoint>",
    "flutter test --no-pub --reporter expanded",
    "dart analyze --fatal-infos lib test integration_test",
    "node --test <14 documented local regression files>",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs --base 0b03f828655408d99bf51e80395de241ec25f295"
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
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

New explicit sessions suite runs22 receiving and15 auth completion cases in the isolated Android integration binding. Receiving cases cover exact-route dismissal, cached owner/copy actions, owner/friend/payment views, fullscreen QR plus newer unrelated dialog, and late clipboard feedback across account switch/same-account relogin. QR PNG is generated on-device and served only from device loopback. Auth cases execute the actual form completion/SDK public-session ordering against synthetic device-loopback HTTP, pausing at profile/ledger/storage stages and proving obsolete/disposed completions cannot restore authentication. Profile/ledger/secure-preference and clipboard ports here remain injected; this is not real provider/native clipboard acceptance.

The first combined report incorrectly returned passed: receiving async main awaited setup before registering cases, allowing automatic lifecycle teardown to finish first, followed by an unhandled late-registration error. That report is explicitly REJECTED. Auth15 ran in that attempt; receiving0 did. The adapter now registers synchronously and initializes asynchronous resources in setUpAll. Runner validation rejects late unhandled/framework errors and requires each expected case name in the actual drive log. Its regressions reject the exact observed empty-success shape. Final run 2026-11-13T19-02-53-637Z passed22/15 named cases and both validation steps; lifecycle setup/teardown counts are excluded from case totals.

Host regressions736/736, Node64/64 (including8 runner tests), and fatal-info Dart analysis pass. Earlier local manifest extraction failed because concurrent reporter output repeated active case names; the checked-in explicit22/15-name contract now describes the expected fixture scenarios and is enforced on-device. This was test tooling work; production application behavior did not change in this batch.

## Evidence

[Sanitized results/source hashes/log digests](QA-012-results.json), [case contract](../../integration_test/android_session_cases.json), [receiving adapter](../../integration_test/android_receiving_scope_test.dart), [auth adapter](../../integration_test/android_auth_completion_test.dart), [runner](../../scripts/usb-test.cjs). Final debug auth APK retained locally with digest; receiving final APK was replaced by the next target build and is not independently retained. Neither is a release candidate. Source changes are based on committed QA-0110b03f828.

## Limits and next action

Current physical4KB native fixture acceptance does not establish actual wallet/import/share, clipboard OS behavior, Google/email provider, Storage/RLS, signed upgrade or16KB runtime acceptance. Scheduling probes do not assert notification delivery/taps. Independent integration review remains unverified, so task stays implemented. iOS runtime is deferred per current user instruction. No backend credentials were loaded, no cloud change/production-package clear/uninstall or publication occurred. Next use the guarded suites for current native session regressions, continue remaining Android platform acceptance and obtain exact signed-candidate/provider evidence before release.

2026-11-14T03:09:00+08:00 � Documentation projection/plain/base validation passed:66 tasks/45 findings/87 verification records. Targeted changed-path credential/artifact scan found0 findings across19 owned paths; isolated staged archive passed memory validation and excludes ignored live config/build artifacts. Diff whitespace validation passed. This is checkpoint hygiene, not release approval.
