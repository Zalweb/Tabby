# QA-027 — Native intent ownership and cold reminder handoff

```json verification-metadata
{
  "id": "VER-QA-027-NATIVE-INTENTS",
  "task_ids": [
    "QA-027",
    "QA-018",
    "HOME-004",
    "QA-001",
    "REL-001"
  ],
  "timestamp": "2026-11-17T10:29:05.386Z",
  "tested_commit": "d0d07126da9b05d29dc8860508e44cd752cbda5a",
  "dirty_tree": true,
  "environment": "Windows / real Lenovo TB321FU API36 ARM64 4KB / normal isolated main.dart app and actual spare Google recipient / approved Azure migration functions / production-key normal16",
  "commands": [
    "Gradle :app:testDebugUnitTest --tests com.zalweb.tabby.PushTapDeliveryTest --tests com.zalweb.tabby.PushEnvelopeTest (red4/2fail; green4/0fail)",
    "Actual frozen-source isolated normal debug build and in-place test update",
    "Actual FCM data-only probe to existing approved test group; own native cache/event-key hash and unique native drawer card selection",
    "Warm PID equality and package-UID SIGKILL with PID absent immediately before cold native drawer tap; isolated destination screen observation",
    "Guarded signed normal16 build, no source drift; verify-android-artifact; actual compiled Android metadata; in-place update and pulled-byte digest",
    "Read-only final live financial fingerprints/sender retirement/recipient/zero-job integrity"
  ],
  "checks": [
    {
      "category": "native-regression",
      "outcome": "passed"
    },
    {
      "category": "compiled-native-link-ownership",
      "outcome": "passed"
    },
    {
      "category": "live-notification-tap",
      "outcome": "passed"
    },
    {
      "category": "cold-notification-tap",
      "outcome": "passed"
    },
    {
      "category": "android-device",
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

The exact owned notification opened the router **Page Not Found** screen. Earlier user wording did not establish a null tab model; the independently reproduced descending cursor failure was real but did not explain this route error. The native PendingIntent uses a unique internal URI for event identity. Flutter default URL handling was also interpreting that URI as a route. Disabling that handler fixed actual warm taps while preserving the URI, OAuth filter and authenticated notification coordinator. [Flutter guidance](https://docs.flutter.dev/release/breaking-changes/deep-links-flag-change) explains plugin ownership; [FlutterFragmentActivity contract](https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterFragmentActivity.html) describes initial Intent-derived routing. Actual installed Supabase source uses app_links and filters Auth callbacks, with the native plugin listener independent of Flutter route handling.

Cold tapping after confirmed process death then opened Home, not the group. Native onNewIntent could destructively consume intent extras once the channel existed but before Dart installed its listener. PushTapDelivery now defers that read until the initialTap handshake; a later/newer Android Intent remains available, and takePushTap still checks the current account/binding when consumed. Warm delivery after handshake remains immediate. Two native regressions reproduce early consumption and premature scope checking; original envelope tests pass. Final4/4 pass. Cold native logs confirm newIntent plus a present initial tap after readiness, without any payload values.

## Evidence

Both final **warm and cold physical notification taps** open Tabby QA notification check showing the spare recipient owes the tagged sender **PHP1.00**. Warm retains the same PID. Cold kills only the isolated UID process, confirms absence immediately before native touch and restores the real spare Google session before showing authorized ledger data. No force-stop, data clear, user attestation or mock pass is substituted. UIAutomator could identify the SystemUI card but not the Flutter destination tree; actual screen inspection supplies the destination evidence, and private images were removed. [Sanitized results](QA-027-native-results.json).

Original business group/individual events prove real queue/trigger/gateway/worker acceptance. Repeats use explicit direct transport events to that same existing group and do not create another expense/business reminder or rewind a lease/cooldown. Final read-only SQL proves preexisting financial fingerprints unchanged, sender access still retired, recipient preserved and no pending/sending jobs. Current integrated826 host tests/clean analysis and prior754 owned tests remain separately scoped.

Normal1.0.4+16 build passed with zero source drift. Exact installed digest `02dd7199462e1ffc1b24372aa1e95c8b76a8b893475899982220cd3c9e240f8f`, production certificate, nondebug/ZIP/ELF checks and compiled opt-out/OAuth filter/native push service pass. In-place15-to16 update preserves original firstInstallTime and owner data/session; .usbtest and .entrytest retained. All9 delivery-source hashes match the physically tested debug snapshot. Current QA-029 UI was included and independently adopted by that owner. An earlier16 build failed a stale generated integration-test plugin registration; it was not installed. Only ignored generated tooling was regenerated before successful serialized rebuilding.

## Limits and next action

This closes the observed warm/cold tap defect on this API36/4KB tablet; it does not establish every Android lifecycle or a final production GO. Independent review/clean integrated candidate, exact-release16 16KB runtime, remaining backend/cutover and account lifecycle checks remain. Fresh manual Google browser login after the native change remains unverified; actual session restoration/authorized reads pass. No iOS runtime, scheduler enablement, billing, public release or owner financial seed. Root build/device reservation released to QA-029 for its final entry fixture only; subsequent normal update must exceed16.
