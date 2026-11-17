# QA-022 — Working Google sign-in and scoped callback failures

```json verification-metadata
{
  "id": "VER-QA-022-GOOGLE",
  "task_ids": [
    "QA-022",
    "QA-001",
    "REL-001",
    "AUTH-001"
  ],
  "timestamp": "2026-11-17T06:55:25.371Z",
  "tested_commit": "1c1d8373829ddd46eed1dd281a90441d129c1faf",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 / Dart3.13.7 / actual Lenovo TB321FU API36 ARM64 4KB over USB / approved Azure migration Auth / manual real Google owner sign-in",
  "commands": [
    "flutter test --no-pub test/features/auth_completion_scope_test.dart test/features/google_auth_configuration_test.dart",
    "flutter test --no-pub --concurrency 2 --timeout 2m (integrated QA-024 run)",
    "dart analyze --fatal-infos lib test integration_test",
    "node --test (76 release/worker/tooling contracts)",
    "python deploy/azure-full/test_google_callback.py",
    "node scripts/usb-test.cjs --suite sessions",
    "Reviewed configure-google-callback.py via Azure RunCommand; encrypted backup/recovery proof; auth-only recreate; scoped read-only account/session and request-status verification",
    "Same-key normal app in-place12 update by QA-024; installed byte/certificate/ZIP/ELF verification; isolated test-package uninstall only",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs; node scripts/check-project-memory.cjs --base 1c1d8373829ddd46eed1dd281a90441d129c1faf; git diff --check"
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
      "category": "oauth-handoff",
      "outcome": "passed"
    },
    {
      "category": "live-oauth-config",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "real-auth-provider",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
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

Google browser opening is a pending handoff, and only an acknowledged current SDK Session completes native sign-in. Login now shows neutral browser instructions, reports actual launch/callback failure, handles cancellation, and preserves exact-session/generation and mounted guards. The repository returns explicit authenticated/browserOpened/cancelled outcomes. A missing native token falls back once. Callback errors are observed only while that form's current attempt/session is active; disposed/later-account callbacks cannot change the form. No error descriptions, codes, credentials or private callback URLs are displayed.

Corrected original-source regression produced two real UI failures (false pending error and silent browser-launch failure), plus a disposed-form control pass. An initial missing linkDelegate fixture compile failure was not product evidence. An intermediate missing-ID-token repair launched the browser twice; the new count assertion reproduced it and the common single fallback corrected it. Final29 focused, integrated759 full Flutter,76 Node,5 configuration guards and clean full analysis pass. QA-022 final3 broad run stopped at suite loading; incomplete analysis-final3 also has no terminal pass. Both retained as interrupted attempts; later completed integrated full and analysis-final4 results supersede them.

Final physical USB run passed48 named cases:26 auth and22 receiving. These invoke actual production forms/SDK and local HTTP with explicitly injected native Google/browser ports, so no personal picker or external sign-in occurs in fixtures. Earlier44-case run is dated evidence. The final temporary .usbtest package was uninstalled; normal com.zalweb.tabby12 and firstInstallTime remain intact. No main data clear/uninstall, logout, sample financial record or private Home screenshot.

The Azure authorize endpoint initially rejected a missing provider redirect. Reviewed callback-only operator repaired the existing enabled Google provider after encrypted recoverable backup. Google then rejected the Console redirect until the user added the exact URI. Subsequent real callback failed invalid_client; a synthetic-invalid-code probe independently rejected the old client pair. The user supplied an additional matching Web-client secret in a protected ignored file. Sealed transfer, incoming credential challenge (invalid_grant for deliberately synthetic code), encrypted prior-provider backup, auth-only restart and settings guards all passed. The new encrypted current-provider capsule is retained so a later application reconfiguration cannot restore the stale secret. Only the callback/that existing provider secret changed. Signup stayed disabled; no financial/source-project mutation, Firebase billing, scheduler or global cutover.

User then reported **Home opens**. Scoped server read-only verification independently confirms the existing confirmed Google identity, recent sign-in/new session, callback302, token200 and no pending PKCE flow. Account email/IDs, raw logs, OAuth state/codes and secrets are excluded from shared evidence. This closes the reported real browser OAuth failure on the tablet. It does not prove every native-provider lifecycle or all production journeys.

Normal release12 combined this repair with separate QA-024 presentation. Pulled installed APK digest3747e7d8e81599f95d5a7bc567decccd5804cb1e53cbc2716f50e830f0d62206 exactly matches the same-key artifact; certificate4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a, nondebuggable, ZIP/ELF16KB checks pass. Its build-source hashes match current login/repository/dependency inputs and no source changed during build. This is private dirty-tree acceptance, not a clean production candidate or public publication.

## Evidence

[Sanitized source/results and operator hashes](QA-022-results.json), [auth regressions](../../test/features/auth_completion_scope_test.dart), [operator guards](../../deploy/azure-full/test_google_callback.py). Ignored local run2026-11-17T06-48-41-412Z retains all48 named device cases. QA-024's completed full759 log is independently checked for all four newest callback-error cases; QA-022 analysis-final4 completes cleanly. Auth-only commit snapshot is separately verified before commit and keeps the pre-QA-024 UI to avoid claiming/staging other work.

Provider setup follows [Supabase self-hosted OAuth](https://supabase.com/docs/guides/self-hosting/self-hosted-oauth) and [Google OAuth client management](https://support.google.com/cloud/answer/15549257). The self-hosted callback is API_EXTERNAL_URL plus /callback; the public API URL includes /auth/v1. Synthetic-code errors diagnose client authentication only; the manual Home result plus real new server session proves actual sign-in.

## Limits and next action

Independent integration review remains open; task implemented, not complete. Keep Android main signed in and preserve cloud history. Finish free Firebase project selection/configuration and real background push, verified SMTP, final source/destination delta/cutover and remaining financial/Storage/lifecycle acceptance. iOS runtime deferred by user. No public release or production-ready claim. Review the separate auth commit, then continue the full acceptance backlog.

2026-11-17T06:57:12.570Z — Separate owned-source verification: full747 Flutter tests pass in the isolated task-base checkout with current auth-only deltas and prior login presentation. This independently verifies the intended source commit while the integrated759 run verifies the concurrent presentation combination. Working memory refresh/plain pass78/45/100; working base coverage fails only unrelated unowned skill-installation paths. No coverage broadened to hide them.

2026-11-17T06:58:10.266Z — Final owned checkout:747 full tests and clean analysis pass. Owned memory refresh/plain/base checks pass76 tasks/45 findings/98 verification records after moving this task's temporary logs into ignored evidence storage; initial isolated base check correctly flagged those untracked root logs. No coverage exception added. Git diff whitespace clean; known Google secret, supplied owner email and machine-specific private path scan0 findings. Deployed credential operator SHA matches recorded source.
