# QA-005 — Account-bound friend requests and truthful acknowledgments

```json verification-metadata
{
  "id": "VER-QA-005-SOCIAL",
  "task_ids": [
    "QA-005",
    "PRO-003",
    "SEC-004"
  ],
  "timestamp": "2026-11-13T18:36:38.648+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Codex root / Windows; Flutter3.47.8/Dart3.13.7; real installed Supabase SDK using loopback synthetic HTTP/session fixtures and Flutter widget tests. No native/device/remote account acceptance.",
  "commands": [
    "flutter test --no-pub --reporter expanded test/features/friend_request_transport_test.dart test/features/friend_connection_scope_test.dart test/features/connections_screen_test.dart",
    "flutter test --no-pub --reporter expanded (final697 tests)",
    "dart analyze --fatal-infos lib test integration_test",
    "flutter build apk --debug --no-pub --dart-define=TABBY_USB_TEST=true",
    "aapt dump badging build/app/outputs/flutter-apk/app-debug.apk",
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
      "category": "real-platform-acceptance",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

| Finding | Before / reproduction | Implemented and observed |
|---|---|---|
| Obsolete friend results | Delayed lookup/send/list/respond results survived another account or same-account relogin; notifier could insert an old outgoing request into the new state. | Capture session generation at each repository/notifier entry and reject obsolete completion. Parse outgoing requests using captured account, validate owner/status/UUID identities and reject wrong list owner. Eight transport account/relogin controls plus notifier regression and positive current-session controls pass. |
| Unchecked decision acknowledgment | Wrong request/status or malformed/incomplete tab acknowledgment reported success. | Validate exact request ID and expected accepted/declined status; accepted tab must be UUID, declined tab remains the SQL-defined empty string. Valid accept/decline compatibility and four malformed controls pass. |
| Stale ConnectByIdSheet | Lookup/found/send state survived account changes and relogin. | AccountDraftGuard plus captured-session checks dismiss the old route and ignore late callbacks in all three phases. Six lifecycle widget fixtures pass. |
| Edited ID sends to different identity | Editing the text after lookup retained the displayed person but sent using newly entered text; delayed old lookup also appeared after edit. | Invalidate lookup generation/match/message on edit; retain matched normalized code; sending requires that code and freezes editing/search while pending. Two regressions and a normal successful-send control pass. |
| Opposing pending responses | Rapid Accept/Decline taps issued two conflicting requests. | Per-request in-flight guard and disabled actions/progress indicator permit one decision. Existing request chrome and acknowledgment assertions remain. |

Final full regression697/697 passes; final analysis reports no issues; isolated Android debug build passed19.9s. Actual badging confirms com.zalweb.tabby.usbtest, version1.0.4+5, debuggable. This is not a signed release candidate or native runtime test.

### Failure history and negative findings

- Initial loopback fixture incorrectly decoded JSON null for zero-argument RPCs, producing fixture errors/timeouts. Corrected it before using failures as product evidence. Corrected original-source transport run:1 pass,13 failures. Widget reproduction grew from6 to8 failures when edited-ID cases were added.
- Initial repaired code had a nullable String compile error, then three brace analyzer infos; corrected before final acceptance. Focused22/22 and neighboring60/60 passed; expanded positive/single-action suite26/26 passed. Full checkpoint692/692 passed before the last five controls; final full run697/697 supersedes it.
- The busy-button reproduction initially queried the Tooltip as an IconButton; corrected the finder before observing the actual two-call defect.
- Investigated possible token switching before SDK dispatch. Both actual-SDK synthetic controls kept initiating A authorization even after B signed in before awaiting. They pass without transport changes. No dispatch vulnerability, pinned-token repair or real provider result is claimed.
- SQL inspection disproved an initial decline-null suspicion: valid decline returns an empty string. No migration/backend/wire change was needed.

## Evidence

[SDK transport tests](../../test/features/friend_request_transport_test.dart), [account/identity widget tests](../../test/features/friend_connection_scope_test.dart), [pending-action UI tests](../../test/features/connections_screen_test.dart); [repository](../../lib/features/tabs/data/supabase_tabby_repository.dart), [provider](../../lib/features/tabs/application/tabby_providers.dart), [profile sheet](../../lib/features/profile/presentation/profile_screen.dart), [connections](../../lib/features/connections/presentation/connections_screen.dart).

[Final source/result manifest](QA-005-results.json) records 456 source hashes, ignored local log hashes, debug APK digest and preservation checks. Logs .dart_tool/readiness/qa005-* retain initial failures and final results; they use synthetic accounts and contain no privileged credentials or private financial/media records. Test HTTP overrides reject external networking. Background endpoint/Realtime fixture warnings do not establish real Realtime behavior. QA-003/004 historical artifacts remain unchanged. Backend/migration/worker/tooling hashes match QA-004, so those suites were not rerun for this client-only change. Direct installed Dart/Flutter snapshot invocations are retained in prior evidence.

## Limits and next action

Task is implemented, not verified/complete. Full production review remains active and production NO-GO. Native Android/iOS multi-account lifecycle, actual Auth/Realtime/provider/Storage acceptance, independent integration review and exact clean signed-candidate/upgrade/16KB acceptance remain open. No deployment, endpoint cutover, remote mutation, message, public release, signup/scheduler/M2 activation or staging/commit occurred. Continue source review, then obtain the named platform/reviewer evidence.
