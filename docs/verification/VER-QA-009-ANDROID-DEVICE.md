# VER-QA-009-ANDROID-DEVICE

```json verification-metadata
{
  "id": "VER-QA-009-ANDROID-DEVICE",
  "task_ids": [
    "QA-009"
  ],
  "timestamp": "2026-11-14T03:06:06+08:00",
  "tested_commit": "0b03f828655408d99bf51e80395de241ec25f295",
  "dirty_tree": true,
  "environment": "Physical Lenovo TB321FU Android API36,4096-byte pages; paired TLS Wi-Fi; isolated local-fixture debug package",
  "commands": [
    "adb mdns services; explicit user-assisted manual TLS pairing; adb connect <advertised-connection-endpoint>",
    "node scripts/usb-test.cjs --suite smoke --transport wifi --device <advertised-connection-endpoint>",
    "node scripts/usb-test.cjs --suite matrix --transport wifi --device <advertised-connection-endpoint>"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "android-device",
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

This dated record supersedes the [earlier unavailable transport](VER-QA-009-ANDROID-TRANSPORT.md), without changing its historical outcome. User now explicitly requests Android-only runtime work and supplied manual pairing details. Pairing succeeded; the separate advertised connection service was then connected and the previously authorized physical hardware/model rechecked before every test installation. Pairing codes are omitted from all shared evidence.

Smoke seed1 plus4 cases passed: native encrypted draft persistence across a process stop, owner isolation, persisted correct/wrong PIN checks, real notification preference scheduling/cancellation and touch UI. Matrix seed1 plus7 cases passed: persisted PIN cold-start navigation, real600k PBKDF2 and five-failure throttling/reopen, synthetic dashboard, settled reminder cancellation, preference/permission gates, and background/force-stop scheduling probes. Notification delivery/tap is NOT asserted. Both actual drive logs were additionally checked using the strengthened QA-012 clean-output validator.

Earlier transport observations are retained: preflight connected, then the TLS port changed during build and the hardware guard stopped before install; another endpoint refused connection. After the user's manual pairing, smoke and matrix completed. These failures are transport evidence, not failed app assertions.

## Evidence

Sanitized run details, digests and source identity: [QA-012 results](QA-012-results.json). Accepted local UTC run IDs: smoke 2026-11-13T18-45-54-817Z; matrix 2026-11-13T18-48-45-892Z. Raw logs/reports remain ignored locally. Installed production package was present and preserved; only com.zalweb.tabby.usbtest was installed/permission-granted/force-stopped. No live suite/backend mutation or real financial data was read.

## Limits and next action

This passes the scoped local-fixture smoke/matrix task category, not broad Android M1/release acceptance. Continue native session regressions, actual notification delivery/taps, picker process death, low-memory/restore, provider/wallet,16KB runtime and signed upgrade acceptance. Independent integration review remains open. iOS runtime is deferred for this Android-only phase, not passed. No deployment/publication occurred.
