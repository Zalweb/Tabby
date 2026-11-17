# QA-002 paired Wi-Fi tablet acceptance

```json verification-metadata
{
  "id": "VER-QA-002-WIFI-TABLET",
  "task_ids": ["QA-002"],
  "timestamp": "2026-11-13T11:57:06.621+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Physical Lenovo TB321FU/API36/4096-byte pages; explicitly user-authorized already paired Android TLS Wi-Fi debugging; Windows Node26/Flutter3.47.8/Dart3.13.7. Isolated com.zalweb.tabby.usbtest debug package; real Azure HTTPS test backend and synthetic GoTrue account.",
  "commands": [
    "adb mdns services; adb connect <advertised-private-IP:TLS-port>",
    "node scripts/usb-test.cjs --suite preflight --transport wifi --device <target>",
    "dart analyze integration_test/usb_live_test.dart",
    "node scripts/usb-test.cjs --suite live --transport wifi --device <target> --live-config .env.usb-live.json",
    "node scripts/usb-test.cjs --suite smoke --transport wifi --device <target>",
    "node scripts/usb-test.cjs --suite matrix --transport wifi --device <target>",
    "node --test scripts/usb-test.test.cjs"
  ],
  "checks": [
    {"category":"automation-regression","outcome":"passed"},
    {"category":"paired-wifi-preflight","outcome":"passed"},
    {"category":"tablet-live-auth","outcome":"passed"},
    {"category":"tablet-live-realtime","outcome":"passed"},
    {"category":"analysis","outcome":"passed"},
    {"category":"tablet-device","outcome":"passed"},
    {"category":"background-delivery","outcome":"unverified"},
    {"category":"integration-review","outcome":"unverified"}
  ]
}
```

## Expected and actual results

The user's explicit instruction on2026-11-13 superseded the earlier USB-only restriction. ADB advertised the tablet's TLS-connect service; existing authorized pairing connected successfully without a pairing-code request, legacy `tcpip`, network scanning or USB fallback. Preflight verified physical model/API/page size, hardware serial and installed production package. Added opt-in `--transport wifi --device <private-IP:TLS-port>` while retaining USB defaults. Private IPv4/TLS-advertisement validation, hardware identity rechecks and real APK badging protect target selection/package isolation. All5 runner safety regressions passed; the combined host suite passed27/27.

First tablet live execution signed in and read its fixture profile, then failed because the new smoke fixture incorrectly expected direct acknowledgment-table access. Current migration20261102000012 intentionally revokes that access and exposes review state through an authorizing RPC. Corrected the fixture to require table denial and the real review RPC's `42501 / Expense party required` response for a nonexistent/nonparty transaction. No backend grants were broadened. Scoped Dart analysis passed. The superseding live run passed: real Auth session/getUser, own profile, current review contract/party denial, private review-table denial and private rollout-flag denial.

Superseding2026-11-13T11:45:00+08:00: native smoke and the broader scripted matrix both passed, each with a separate seed APK and actual force-stop between seed and test execution. Smoke covered encrypted draft owner isolation/persistence, stored PIN correct/wrong entry, notification permission/preference gates and touch input. The7-case matrix covered cold lock/PIN navigation, account-lock isolation, resumed notification handling, settlement reminder cancellation, permission/preference gates and scheduling-only background/force-stop probes. These14 physical tests across live/seed/smoke/matrix entry points passed; notification delivery itself was not asserted. No production package uninstall/data clearing occurred.

## Evidence

Sources: [runner](../../scripts/usb-test.cjs), [safety tests](../../scripts/usb-test.test.cjs), [live fixture](../../integration_test/usb_live_test.dart), [usage](../project/USB_TESTING.md). Ignored Wi-Fi preflight report: `.dart_tool/usb-tests/2026-11-13T03-31-17-313Z/report.json`. Failed initial live report: `2026-11-13T03-32-16-355Z/report.json` in that directory. Superseding passed live report: `2026-11-13T03-37-58-414Z/report.json`. Passed smoke report: `.dart_tool/usb-tests/2026-11-13T03-39-14-971Z/report.json`; passed matrix report: `.dart_tool/usb-tests/2026-11-13T03-41-37-003Z/report.json`. All5 drive logs report All tests passed. Backend26-check and restore evidence: [Azure restore/live record](VER-QA-002-AZURE-RESTORE.md). No fixture passwords, client configuration, private APKs or production-app data are shared.

## Limits and next action

Physical live/smoke/scripted matrix are passed. Keep independent integration review and broader QA-001/REL-001 gates open. This debug APK is isolated; it does not update the installed production client or authorize a release. Pending notification probes do not establish background/reboot/force-stop/FCM delivery; native biometric, picker process death, 16KB runtime, signed upgrade, Google provider and full production cutover acceptance remain separate. USB physical transport still has no successful run; Wi-Fi is the explicitly authorized replacement for current testing.

### 2026-11-13T11:57:06.621+08:00 ? Real tablet Realtime delivery

Extended the same live fixture to require an Admin-tagged synthetic account, subscribe to its own public.users UPDATE stream, change its own display name through update_profile_v2, receive the matching Azure event and restore the original fixture display name. Initial extended execution joined successfully but timed out waiting for data. The installed SDK and pinned Realtime2.148.3 source establish that channel join precedes asynchronous CDC readiness. Enabled replicationReady and waited for the explicit system/ok readiness notification before writing; the superseding full live execution passed. No server replication setting or authorization policy was changed. A transient misplaced Dart import was corrected before deployment; scoped analysis then passed. Latest passed report: `.dart_tool/usb-tests/2026-11-13T03-53-22-439Z/report.json`; earlier timeout report: `2026-11-13T03-48-06-140Z/report.json`. Full cross-account/lifecycle Realtime authorization and release gates remain open.
