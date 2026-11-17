# VER-SEC-003 — PIN verifier and persistent attempt limits

```json verification-metadata
{
  "id": "VER-SEC-003",
  "task_ids": [
    "SEC-003"
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
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T14:04:21.021Z",
  "tested_commit": "1b916c5b35fa38de9b1589976c8b8e4c389948a2",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8; real cryptography 2.9.0 production derivation and explicit storage/auth mocks; no Android device.",
  "commands": [
    "flutter test test/features/pin_attempts_test.dart test/features/security_settings_test.dart test/features/cold_lock_test.dart",
    "flutter test test/features/e2e_all_screens_buttons_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 1b916c5b35fa38de9b1589976c8b8e4c389948a2",
    "git diff --check"
  ]
}
```

## Expected and actual results

302/302 final full suite, 13/13 focused PIN/settings/gate tests, 12/12 broad UI file; analysis clean. Tests exercise the actual 600,000-iteration service, a known PBKDF2-SHA256 vector, persisted lockout across service instances, concurrent attempts, account isolation, successful counter reset, legacy wrong/correct upgrade behavior, malformed record rejection and authenticated reset cancellation/success.

## Evidence

[PIN regressions](../../test/features/pin_attempts_test.dart), [settings regressions](../../test/features/security_settings_test.dart). Attempt-policy tests use an injected clock and cheap derivation; a separate test runs production derivation. Broad widget flow uses an explicit in-memory PIN boundary. Initial full run failed 3 UI tests from asynchronous derivation outliving the profile test; corrected its boundary, final full run passed. Earlier overlapping Flutter launch hit a shared test-cache error and was stopped.

The cost follows [OWASP PBKDF2 guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2); algorithm implementation uses [cryptography API](https://pub.dev/documentation/cryptography/2.9.0/cryptography/Pbkdf2-class.html). A 4–6 digit app PIN still depends on platform secure storage and persisted online attempt limits.

## Limits and next action

Secure storage and platform authentication are mocked. Real keystore/restart/device clock, biometric/device credential cancellation and supported-phone latency remain unverified. Recovery requires fresh device authentication and affects only local app protection. No deployment/publication. Run Android acceptance before verified/complete.
