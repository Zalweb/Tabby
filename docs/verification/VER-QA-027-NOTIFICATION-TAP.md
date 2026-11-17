# QA-027 — Load notification targets with an ascending ledger cursor

```json verification-metadata
{
  "id": "VER-QA-027-NOTIFICATION-TAP",
  "task_ids": [
    "QA-027",
    "QA-018",
    "HOME-004",
    "AND-004",
    "QA-001",
    "REL-001"
  ],
  "timestamp": "2026-11-17T09:35:42.795Z",
  "tested_commit": "1f8b0bb7deaa05c3602a1d41c71f194818738fba",
  "dirty_tree": true,
  "environment": "Windows / real Lenovo TB321FU API36 ARM64 / isolated normal main.dart app / manual spare Google recipient / approved Azure migration backend",
  "commands": [
    "flutter test --no-pub test/features/ledger_header_transport_test.dart test/features/ledger_page_loader_test.dart test/core/notification_tab_readiness_test.dart test/core/background_reminders_test.dart",
    "dart analyze --fatal-infos changed notification/repository/main sources and new tests",
    "frozen-source offline dependency resolution and real Flutter debug APK build",
    "guarded adb install -r isolated package; no clear/uninstall",
    "real queue/worker acceptance followed by distinct direct transport probe for corrected tap; native posted-event hash comparison"
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
      "category": "live-notification-tap",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

Actual notification taps in the spare Google account open Tab not found. First repair awaited a scoped refresh before routing, but the user confirmed it still failed. A fresh isolated-process diagnostic then showed `FormatException: Invalid tab cursor`. The installed PostgREST2.9.1 SDK defaults to descending order; the production request omitted direction while the loader enforces increasing IDs and `id > after`. Explicit ascending order fixes the wire contract without weakening membership, RLS, session or newest-tap checks. The loader continues rejecting malformed/nonadvancing pages.

## Evidence

The HTTP-boundary regression drives the actual SDK query into the real ledger loader across101 synthetic UUID headers and two requests. It reproduces the same exception before the fix and passes after it;24 focused tests and scoped analysis pass. First fake HTTP response lacked its request object, yielding a harness null error; this was corrected before recording the product reproduction. The first root rebuild drifted during concurrent Profile work and was rejected despite Flutter exit0. The final immutable snapshot build has zero source drift, and exact APK digest b1a9edf1dca6b40fc37491cb7ffaa7bf5c32b5b24c75eedcffffbbf98682e576 is installed in place in `com.zalweb.tabby.usbtest`, retaining its firstInstallTime and spare session. Normal main14 remains untouched. [Sanitized results](QA-027-results.json).

Actual group trigger/job/gateway/worker acceptance and matching native event cache preceded the first failed tap. To repeat after the cursor correction without another expense or overriding the six-hour rule, a distinct direct data-only transport event targets the same existing test group. This is transport/tap verification, not a new queue acceptance. First provider-accepted attempt had no posted event and later diagnostics found the app resumed; repeat used the same event while explicitly background and its exact posted-cache hash matches. Requested am-kill was asynchronous and PID remained before dispatch, so no process-death pass is claimed here.

## Limits and next action

Final user tap remains unverified. The earlier802-test full run predates the cursor change; current integrated tests and full analysis belong to the active UI integration and are recorded separately when terminal. Independent review, normal signed delivery, additional lifecycle checks and synthetic sender retirement remain open. No scheduler activation, public release or iOS runtime claimed.


2026-11-17T09:38:53.148Z — Superseding cleanup checkpoint: exact-tag synthetic sender access retired successfully; real recipient preserved and preexisting financial fingerprints unchanged. Earlier pending-retirement statements are historical. QA-027 is implemented, final physical tap/review still unverified. Current integrated819-pass UI run is additional host evidence; owned commit snapshot validation follows.


2026-11-17T09:42:46.633Z — Terminal source-only snapshot:754 full tests,24 focused cases and full lib/test/integration analysis pass. Normal main15 independently pulled and verified at exact digest 1985498fb5508f516c8ce6bb30108cec983e75737e26256778bf3a277b25e15a with production certificate/ZIP/ELF checks and preserved original firstInstallTime. Integrated release manifest matches all4 corrected functional source hashes. This supersedes earlier no-normal-delivery/pending-owned-check statements. Final actual tap remains unverified.


2026-11-17T10:29:05.386Z — Superseding actual native outcome: warm and killed-process/cold drawer taps now show the correct existing test group/PHP1.00 after explicit link ownership and Dart-listener handshake repair. Signed normal16 delivered in place with preserved data/session; final live financial integrity passes. Prior pending/failed/native14/15 statements are historical. [Current native evidence](VER-QA-027-NATIVE-INTENTS.md) and [results](QA-027-native-results.json). Other lifecycle/review/production gates remain open.
