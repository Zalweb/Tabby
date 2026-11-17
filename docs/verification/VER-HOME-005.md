# VER-HOME-005 — Account-bound Android background reminders

```json verification-metadata
{
  "id": "VER-HOME-005",
  "task_ids": [
    "HOME-004",
    "HOME-003"
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
      "category": "kotlin-unit",
      "outcome": "passed"
    },
    {
      "category": "worker-unit",
      "outcome": "passed"
    },
    {
      "category": "deno-check",
      "outcome": "passed"
    },
    {
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T04:46:10.723Z",
  "tested_commit": "0dfab2d69af69cce91cf4640644104b8a477e0b4",
  "dirty_tree": true,
  "environment": "Windows; Flutter 3.47.8, Android Studio JDK, Android debug compilation and host JVM tests. Explicit secure-storage/transport mocks and synthetic tokens/UUIDs; Node26, isolated Deno2.5.6. Disposable native PostgreSQL17.11 plus PGlite financial migration subset through 20261101000006 with synthetic JWT/roles and storage fixture. No actual FCM/Supabase HTTP/deployment, configured Firebase app or connected Android device.",
  "commands": [
    "flutter test test/core/background_reminders_test.dart test/core/account_notifications_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "android/gradlew.bat :app:testDebugUnitTest",
    "node --test scripts/test-reminder-push-worker.mjs",
    "deno check supabase/functions/reminder-push/index.ts",
    "node scripts/test-backend-native.cjs",
    "node scripts/test-money-commands.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 0dfab2d",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed 423/423 and Dart analysis clean. New focused push/tap plus preference suite passed 23/23, including ten new account-registration/tap regressions. Android debug APK builds; Gradle app:testDebugUnitTest passed two Kotlin envelope/binding tests. Six Node worker tests passed, including real synthetic-key OAuth signing/verification, data-only privacy payload, HTTP error classification, response loss, stale leases and worker request gates. Deno 2.5.6 checked the Edge entry point. Native PostgreSQL 17.11 and PostgreSQL/WASM source subsets passed background role/binding/opt-out/expiry/membership/settlement/retry-limit/token-rotation contracts. Eight independent native service-role workers acquire disjoint ready-job leases; existing financial/reminder concurrency contracts pass.

## Evidence

[Flutter account/tap tests](../../test/core/background_reminders_test.dart), [Kotlin receiver policy tests](../../android/app/src/test/kotlin/com/zalweb/tabby/PushEnvelopeTest.kt), [worker tests](../../scripts/test-reminder-push-worker.mjs), [native role/queue contracts](../../scripts/test-background-reminders.cjs), [independent workers](../../scripts/test-backend-native.cjs), [migration](../../supabase/migrations/20261101000006_background_reminders.sql), [setup/contract](../project/BACKGROUND_REMINDERS.md). The worker and receiver use data-only account/binding/event/tab identifiers. Synthetic OAuth test generates an ephemeral key and verifies the signature locally; it never requests a real token. SQL worker acceptance is distinct from provider acceptance, native display and actual delivery.

## Limits and next action

All live setup/deployment/provider/device checks remain open. Debug build/JVM tests do not establish background receipt, Android permission or cold-tap behavior. No credentials, tokens or private financial data are committed. No deployment/publication.
