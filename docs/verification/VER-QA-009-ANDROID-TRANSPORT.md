# QA-009 — Advertised tablet endpoint is not connected

```json verification-metadata
{
  "id": "VER-QA-009-ANDROID-TRANSPORT",
  "task_ids": [
    "QA-009",
    "QA-001",
    "QA-002"
  ],
  "timestamp": "2026-11-14T00:48:44.438+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows ADB; one private TLS mDNS advertisement, no connected/authenticated Android device",
  "commands": [
    "adb devices -l; adb mdns services",
    "adb connect <current-advertised-private-TLS-endpoint>",
    "adb -s <same-endpoint> shell getprop ro.serialno; adb -s <same-endpoint> shell getprop ro.product.model",
    "adb mdns services; adb devices -l"
  ],
  "checks": [
    {
      "category": "discovery",
      "outcome": "passed"
    },
    {
      "category": "paired-tls-connect",
      "outcome": "failed"
    },
    {
      "category": "hardware-identity",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "regression",
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

Fresh Nov14 discovery after the user continuation found one private Android TLS-connect advertisement resembling the earlier authorized tablet service. The planned next action was paired connection and identity-checked preflight, followed by isolated local fixtures.

Actual adb connect to that exact advertised endpoint was actively refused (Windows10061). Hardware/model reads then returned device-not-found. A subsequent read-only inventory still lists zero devices and the same mDNS advertisement. No authenticated handle, actual serial/model/API/page-size or package state can be established. The advertisement does not prove a currently listening transport; the earlier physical QA-002 results retain their own date/source scope.

No runner preflight, build/install for device, smoke, matrix, force-stop, permission change or notification test ran. The production package/data and isolated package were untouched. No pair request, legacy tcpip activation, port guessing or subnet scan occurred. User was asked asynchronously to make the paired tablet available; broader source review continues.

## Evidence

Current task [QA-009](../progress/tasks/QA-009.md), [reviewed runner/protocol](../project/USB_TESTING.md) and historical [paired tablet record](VER-QA-002-WIFI-TABLET.md). Tool terminal observations: one advertised service, connect refusal10061, device-not-found for both reads, subsequent connected-device count0. Endpoint/hardware identifiers are omitted from this shared summary; no credentials or private account data were read.

[QA-008 source/results](QA-008-results.json) remain current for source712-test/analysis/debug packaging. This transport attempt changed no source file or tested artifact and adds no new runtime acceptance.

## Limits and next action

QA-009 is blocked until the previously paired tablet is awake with Wireless debugging listening on the same private network. After availability changes, rediscover its exact TLS endpoint, connect, verify hardware identity and production/test package isolation, then run reviewed local smoke/matrix. Real provider/backend/device journeys, actual notification delivery,16KB runtime, real upgrade, iOS and exact signed release gates remain open. Production remains NO-GO. No production deployment, remote account mutation, device installation, public release or messages occurred.
