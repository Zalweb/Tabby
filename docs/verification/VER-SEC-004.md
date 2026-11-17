# VER-SEC-004 — Actor-bound Auth mutations without shared SDK session replacement

```json verification-metadata
{
  "id": "VER-SEC-004",
  "task_ids": [
    "SEC-004",
    "PRO-001",
    "AUTH-002"
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
      "category": "sdk-boundary",
      "outcome": "passed"
    },
    {
      "category": "android-build",
      "outcome": "passed"
    },
    {
      "category": "web-build",
      "outcome": "passed"
    },
    {
      "category": "auth-provider-integration",
      "outcome": "unverified"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T13:24:07.002Z",
  "tested_commit": "623883218584d4121349514169f0113f98a6e9de",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8; installed GoTrue2.27.2/Supabase Flutter2.17.2 real SDK clients, synthetic JWT/session/user fixtures and MockClient HTTP. Actual SDK exchange consumes the transport-generated S256 verifier in tests. Android debug/JDK and JavaScript web compilation. No live Auth/email, real account/password/token, backend deployment or device.",
  "commands": [
    "flutter test test/features/auth_user_mutation_test.dart test/features/auth_assistance_test.dart test/features/profile_persistence_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "flutter build web",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 6238832",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed520/520; Dart analysis clean; Android debug APK and JavaScript web builds pass. Fifteen new regressions use installed GoTrue2.27.2 clients with synthetic sessions/HTTP to verify A-response/B-session and same-account relogin isolation, no userUpdated emission, password request token binding, email remaining unchanged until actual SDK PKCE exchange, account change during verifier persistence, inconsistent token/user or foreign/malformed acknowledgment rejection, weak/same-password errors, parallel suppression, timeout/late response and guard recovery, failed verifier storage, slow/obsolete PKCE writer ordering. Focused auth/profile suite passed39/39. No SQL changed or deployed in this batch.

## Evidence

[SDK-boundary regressions](../../test/features/auth_user_mutation_test.dart), [captured Auth transport](../../lib/core/services/auth_user_mutation.dart), [serialized SDK-compatible verifier storage](../../lib/core/services/serialized_pkce_storage.dart), [SDK configuration](../../lib/core/config/supabase_config.dart), [recovery writer](../../lib/core/services/recovery_password_update.dart), [email request service](../../lib/features/profile/application/profile_email_change.dart). Captured tokens/passwords remain transient request memory. Only an opaque PKCE verifier uses the existing SDK storage key; no new account token/password persistence or SDK session replacement is introduced.

## Limits and next action

Real Auth/provider and native/browser deep-link lifecycle remain required release checks. Local subject consistency is not cryptographic JWT verification; the real Auth service performs authentication. Synthetic HTTP/SDK compatibility does not prove actual hosted confirmation settings. No SQL/schema changed, real user data or credentials recorded, deployment or publication.
