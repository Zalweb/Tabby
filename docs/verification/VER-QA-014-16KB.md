# QA-014 — Actual Android 16KB encrypted storage and session acceptance

```json verification-metadata
{
  "id": "VER-QA-014-16KB",
  "task_ids": [
    "QA-014"
  ],
  "timestamp": "2026-11-14T14:20:41.074+08:00",
  "tested_commit": "734d80093c1a340c87eab1b2b3b5303372e63319",
  "dirty_tree": true,
  "environment": "API36 Google APIs ps16k x86_64 emulator-5580; actual PAGE_SIZE16384, qemu1; isolated com.zalweb.tabby.usbtest",
  "commands": [
    "node scripts/android-emulator-test.cjs --device emulator-5580 --suite all",
    "dart analyze --fatal-infos lib test integration_test",
    "node --test <16 regression files recorded in QA-018 results>"
  ],
  "checks": [
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "16kb-device",
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

Installed the official API36 google_apis_ps16k/x86_64 image and booted a guarded 16KB runtime. Added an explicit emulator-only runner and four named native storage cases using the real encrypted factory, secure storage and SQLite3MC. All45 named cases passed:4 storage,22 receiving,15 auth and4 local notification/denial cases. A durable operation and10000 encrypted history entries survived force-stop/reinstallation; missing-key open failed closed and preserved ciphertext; an interrupted native legacy import rolled back and retried durably.

Accepted run2026-11-14T04-21-31-633Z, all six named-case contracts passed; no scheduling-only or zero-case success accepted. Native history read3474ms for100 tabs/10000 entries. Final analysis and74 host Node checks recorded in QA-018 results. Prior736 host Flutter tests remain dated QA-012 evidence; production lib/ and host test/ sources unchanged in this batch.

## Evidence

[Sanitized current results, artifacts, source delta and log digests](QA-018-results.json). Tested source is base 734d80093c1a340c87eab1b2b3b5303372e63319 plus the recorded dirty-tree delta. Local SDK/emulator/test-package changes only. Personal tablet production package and real financial data untouched.

## Limits and next action

x86_64 emulator acceptance does not establish ARM64 runtime, all M1 journeys, providers, signed financial queue migration or independent integration review. iOS runtime deferred by user.

Continue exact candidate ARM64/device/provider journeys and integration review. Use the explicit emulator runner; retain paired-tablet guards.
