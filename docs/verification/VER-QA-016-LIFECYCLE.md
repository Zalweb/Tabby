# QA-016 — Actual notification cold launches after process death and emulator reboot

```json verification-metadata
{
  "id": "VER-QA-016-LIFECYCLE",
  "task_ids": [
    "QA-016"
  ],
  "timestamp": "2026-11-14T14:20:41.074+08:00",
  "tested_commit": "734d80093c1a340c87eab1b2b3b5303372e63319",
  "dirty_tree": true,
  "environment": "Isolated API36/16KB x86_64 emulator only; native Android notification drawer and actual Flutter plugin launch details",
  "commands": [
    "node scripts/android-cold-launch-test.cjs --device emulator-5580 --mode closed",
    "node scripts/android-cold-launch-test.cjs --device emulator-5580 --mode reboot"
  ],
  "checks": [
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "android-lifecycle",
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

Added emulator-only lifecycle harness and a synchronously registered native fixture. Actual scheduled notifications were observed in the Android drawer, tapped using freshly observed exact synthetic title bounds, and launched an absent process. Native launch details validated version/account/tab payload plus encrypted draft and persisted PIN. Both closed-process and emulator-reboot runs passed. Only the test app UID can be killed; no package force-stop before delivery. Final harness requires a successful fresh XML dump, unique run path and bounded emulator identity checks.

Accepted closed run2026-11-14T04-47-40-114Z and reboot run2026-11-14T04-50-32-942Z. First closed attempt failed its process-gone precondition with am kill; changed to guarded same-UID process kill. First accepted closed run needed a manual emulator wake; automatic wake was present for accepted reboot. Final closed rerun outcome retained in linked results, including any fresh-screen failures.

## Evidence

[Sanitized current results, artifacts, source delta and log digests](QA-018-results.json). Tested source is base 734d80093c1a340c87eab1b2b3b5303372e63319 plus the recorded dirty-tree delta. Synthetic emulator .usbtest notifications, installs/process death and explicit reboot only. No personal tablet reboot or notification collection, cloud or financial operation.

## Limits and next action

This verifies local alarm cold payload and persisted encrypted fixture state, not real FCM, authenticated membership routing, lock-screen authentication, physical OEM delivery or package-force-stop behavior. Reboot applies only to the owned emulator.

Keep final-source rerun outcomes visible; continue physical OEM/FCM/authenticated cold-tap acceptance and review.

2026-11-14T06:21:51.577Z — Final-source closed rerun2026-11-14T06-16-05-960Z passed unattended, including automatic wake and successful fresh XML check, actual synthetic notification tap and cold payload/encrypted-state validation. Reboot acceptance remains the separately recorded earlier passed run.
