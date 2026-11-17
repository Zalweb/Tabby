# QA-013 — Physical local notification delivery

```json verification-metadata
{
  "id": "VER-QA-013-ANDROID-NOTIFICATIONS",
  "task_ids": [
    "QA-013"
  ],
  "timestamp": "2026-11-14T03:16:51.639+08:00",
  "tested_commit": "dec17d09b7719ce17584f376b0d32d20fcc85796",
  "dirty_tree": true,
  "environment": "Physical Lenovo TB321FU/API36/4096-byte pages; isolated local native notification/secure-preference fixtures over paired TLS Wi-Fi",
  "commands": [
    "node scripts/usb-test.cjs --suite notifications --transport wifi --device <advertised-connection-endpoint>",
    "dart analyze --fatal-infos lib test integration_test",
    "node --test scripts/usb-test.test.cjs",
    "node --test <same14 local regression files recorded in QA-012>",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs --base dec17d09b7719ce17584f376b0d32d20fcc85796"
  ],
  "checks": [
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "notification-local-delivery",
      "outcome": "passed"
    },
    {
      "category": "notification-permission-denial",
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

Four named native cases passed on the physical API36/4KB tablet, using the actual production notification service, Android plugin and encrypted preference store with synthetic local accounts. Immediate notification became active with the expected body/channel; changing account removed it. Disabling preferences removed active notifications and suppressed a subsequent alert. A future reminder became an active Android notification with correct ID/title/body/channel after 5063ms, left the pending list, and cancellation removed the active entry. Exact-alarm access was false; this is actual inexact fallback delivery in this foreground/awake run, not merely a pending request.

The runner then revoked POST_NOTIFICATIONS only for com.zalweb.tabby.usbtest. The next target observed native permission false, enabled account preferences, attempted immediate and scheduled alerts, and verified both active and pending lists empty. The runner finally restored this test-package permission and recorded a passed restoration step. This covers revoked runtime state; it does not exercise the first-run permission dialog. All four required case names and clean output passed runner validation. Initial allowed-only3-case run also passed before expanding to denial; final combined run supersedes it.

Analysis clean;65 Node checks including9 runner checks pass. Production Dart and prior host tests are byte-identical to QA-012, whose736 Flutter results remain dated prior evidence; no redundant full host rerun was needed for these integration-only/runner changes. No app defect was reproduced in this batch.

## Evidence

[Sanitized results/source delta/log digests](QA-013-results.json), [allowed target](../../integration_test/android_notification_delivery_test.dart), [denied target](../../integration_test/android_notification_denied_test.dart), [case contract](../../integration_test/android_notification_cases.json) and [runner](../../scripts/usb-test.cjs). Accepted local UTC run2026-11-13T19-14-37-142Z. NotificationManager is queried inside this application via the installed plugin; no other-app notification dump is collected. Production package remained installed and untouched. The previous [native session checkpoint](VER-QA-012-ANDROID-SESSIONS.md) was committed as dec17d0 with a clean tree immediately afterward.

## Limits and next action

Active entries prove OS posting, not that a person saw/tapped a notification. Scheduled delivery here was foreground/awake; background, closed/force-stop, reboot, locked/cold taps, OEM restrictions, FCM and real provider/backend acceptance remain open. The physical tablet has4KB pages;16KB runtime and signed upgrade/exact candidate remain required. iOS deferred for the current Android-only request. Independent integration review is unverified; task stays implemented. Only isolated package installs/permission revoke-and-restore/fixture notifications and force-stops occurred; no global settings, real data, cloud/deployment or publication change. Next continue remaining Android lifecycle/provider/release acceptance with dedicated fixtures and exact artifacts.

2026-11-14T03:17:28.937+08:00 � Projection/plain/base checks pass:67 tasks/45 findings/88 verification records. Changed-path artifact/credential scan0 findings across17 owned files; staged archive memory check passes with ignored live config/build excluded. Diff whitespace check passes. Checkpoint hygiene only; no release signoff.
