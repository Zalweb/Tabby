# VER-AUTH-002 — Password recovery and confirmation assistance

```json verification-metadata
{
  "id": "VER-AUTH-002",
  "task_ids": [
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
      "category": "android-build",
      "outcome": "passed"
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
  "timestamp": "2026-11-01T04:59:23.474Z",
  "tested_commit": "16cbdd83a108410be192c5387dbe25c0d6309b70",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8, installed Supabase Flutter2.17.2/GoTrue2.27.2 inspected locally; explicit secure-storage mocks, synthetic account/session identifiers and injected email/password ports. Real router/widgets run locally. Android debug compilation with Studio JDK; no device/live auth/email calls.",
  "commands": [
    "flutter test test/features/auth_assistance_test.dart test/features/auth_recovery_routing_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 16cbdd83a108410be192c5387dbe25c0d6309b70",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 438/438; Dart analysis clean. Focused recovery/assistance/router suite passed 15/15. Fifteen new tests cover marker restart/account separation, stale restore, session claims, installed SDK error shapes, email validation/cooldown/response loss/server limits, reset authorization/acknowledgment/failure/retry, old-account completion, real help/reset widget flows, route priority, expired-link help and draft clearing during a pending reset. Android debug APK builds successfully. No real email or backend account was used.

## Evidence

[Assistance/reset regressions](../../test/features/auth_assistance_test.dart), [actual routing tests](../../test/features/auth_recovery_routing_test.dart), [recovery marker](../../lib/core/services/auth_recovery_state.dart), [email service](../../lib/core/services/auth_email_assistance.dart), [guarded update](../../lib/core/services/recovery_password_update.dart), [SDK error adapter](../../lib/core/services/auth_link_failure.dart). No token/link/password is persisted by these services; the marker stores only opaque account/session IDs. A replayed initial recovery event is handled before ordinary navigation, and token refresh of the same session retains the marker. Actual platform callback delivery remains unverified.

## Limits and next action

Service configuration and actual valid/expired/used email-link exchange, browser/native lifecycle, storage restoration and server throttling remain unverified. No auth settings, SMTP, redirect allowlist or remote user data changed. No deployment/publication.
