# QA-008 — Session-bound auth completion and optional preference errors

```json verification-metadata
{
  "id": "VER-QA-008-AUTH",
  "task_ids": [
    "QA-008",
    "AUTH-002",
    "AUTH-003",
    "SEC-004",
    "QA-001",
    "REL-001"
  ],
  "timestamp": "2026-11-14T00:45:38.628+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8/Dart3.13.7 / installed GoTrue2.27.2; loopback synthetic auth/profile and actual Flutter form callbacks, controlled profile/ledger ports. No provider/device lifecycle acceptance.",
  "commands": [
    "flutter test --no-pub --reporter expanded test/features/auth_completion_scope_test.dart",
    "flutter test --no-pub --reporter expanded",
    "dart analyze --fatal-infos lib test integration_test",
    "flutter build apk --debug --no-pub --dart-define=TABBY_USB_TEST=true",
    "aapt dump badging build/app/outputs/flutter-apk/app-debug.apk",
    "adb devices -l; adb mdns services",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs; node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0; git diff --check"
  ],
  "checks": [
    {
      "category": "focused-regression",
      "outcome": "passed"
    },
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "android-debug-build",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "ios-device",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "real-auth-provider",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

| Finding | Corrected fixture reproduction | Repair / final observation |
|---|---|---|
| Obsolete login/signup completion changes global auth/profile flags | Pause the actual last profile HTTP response after installed SDK password/signup success, sign out or replace/relogin session, release response. Both forms reauthenticate the display flag and/or replace the later profile gate. Disposed signup also changes global flags before its mounted check. | Capture acknowledged exact SDK Session and generation, then recheck mounted/generation after every preference/profile/ledger/profile-check await before continuation/global flags/navigation. Seven final-response/disposed scenarios pass. Four additional profile/ledger pause controls verify no subsequent load is started for the later account. |
| Unhandled optional onboarding write | Inject a secure-storage map whose onboarding-key write throws PlatformException. The unawaited write bypasses synchronous try/catch while the ordinary flow completes. Both forms emit unhandled errors. | Await the write inside its existing optional-failure catch and recheck scope afterward. Working/failing storage completion controls all pass, preserving successful auth when this preference cannot persist. |
| First repair discards its own successful sign-in | The installed SDK public auth stream queues signedIn; capturing a stamp immediately after the auth Future then awaiting storage can let that event advance the generation and cancel its own completion. Ordinary controls caught this regression. | Wait for the replayed public SDK auth event, require identical active Session to the acknowledgment, then capture the generation. No internal synchronous SDK stream or fixed delay is used. Both ordinary flows and same-account relogin controls pass. Busy flags clear in finally so obsolete completion does not leave an active spinner. |

Final15/15 focused cases and712/712 full Flutter tests pass. Final scoped Dart analysis reports no issues. Android isolated debug packaging passes62.4s; actual badging is com.zalweb.tabby.usbtest1.0.4+5, debuggable. This is not a signed candidate or native runtime result. Backend/migrations/tooling/native configuration match QA-007; its52-migration SQL evidence remains historical with unchanged source and was not rerun for this client-only repair.

### Harness and failure history

Initial network work began in Flutter fake-async scope and timed out; moving the actual callback into runAsync enabled real loopback IO. A first fake ledger subclass also started production Realtime background/disconnect timers; use a controlled StateNotifier protocol fixture for this dependency instead. Corrected original source then has2 passes,9 product failures. Optional storage uses the real flutter_secure_storage mock platform with a throwing key map; no private storage content is used.

A40ms completion wait was unstable for one positive signup; replaced it by retaining and awaiting the actual form callback Future, keeping the original acceptance assertions. Four added earlier-await controls initially created pause completers in fake scope; allocate those in the real async zone. First repaired scope ordering failed ordinary controls as described above. Analyzer found two explicit mounted guards and test brace/const infos, then three redundant nested consts; corrected before clean analysis. Full712 run passed after production guards; final style changes only remove redundant test consts. No failing assertion was weakened or real platform acceptance inferred.

## Evidence

[Auth completion tests](../../test/features/auth_completion_scope_test.dart), [public acknowledgment helper](../../lib/core/config/supabase_config.dart), [login](../../lib/features/auth/presentation/login_screen.dart) and [signup](../../lib/features/auth/presentation/signup_screen.dart); [final source/results](QA-008-results.json) records 460 source hashes, log hashes and debug APK digest. Ignored .dart_tool/readiness/qa008-* logs retain each failed/corrected checkpoint. Installed GoTrue source signUp/signInWithPassword/_saveSession/public ReplaySubject was inspected locally to establish ordering and session object ownership; the internal-only synchronous stream is deliberately unused. Test overrides reject all external HTTP. The fixture invokes the actual rendered form callback and awaits its terminal Future; profile/ledger dependency ports are explicit local controls. Actual Google native login was not performed.

Fresh ADB discovery has no connected device but a current TLS-connect advertisement for the previously tested tablet. This changes the next action to identity-checked paired Wi-Fi preflight; it does not itself close any device category. The isolated debug APK is retained under ignored .dart_tool/readiness/qa008-debug.apk before future runner artifacts overwrite the shared build output.

## Limits and next action

Production remains NO-GO. Native Android/iOS/provider/callback/account lifecycle, independent integration review and exact signed-release/upgrade/16KB acceptance remain open. No signup activation, remote account creation, actual provider request, deployed migration, cloud change, endpoint switch, publication, staging/commit or messages occurred. Next attempt safe paired-tablet identity/preflight and local-fixture device checks while continuing broader review. Local source repair is not proof of deployed remediation.
