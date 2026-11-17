# QA-014 — One signed normal17 APK on native16KB and physical ARM64

```json verification-metadata
{
  "id": "VER-QA-014-CANDIDATE17",
  "task_ids": [
    "QA-014",
    "QA-001",
    "REL-001",
    "QA-027"
  ],
  "timestamp": "2026-11-17T13:29:14.425Z",
  "tested_commit": "e3ff9042b48fb2b77e9ea1ca0e9581658344ee78",
  "dirty_tree": true,
  "apk_sha256": "626b8084ac4894bdebaa8d9c05e3d385f291ead28a62ba9eafa114bf78bbe3c7",
  "certificate_sha256": "4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a",
  "environment": "Windows / actual official API36 native x86_64 16KB emulator / physical Lenovo TB321FU API36 ARM64 4KB / same signed normal17 bytes",
  "commands": [
    "Frozen main16 source reconstruction with exact recorded hashes; actual release build normal17 for android-arm64,android-x64",
    "verify-android-artifact.cjs against expected production certificate; nondebuggable/ZIP/ELF16KB checks",
    "Guarded emulator main16-to17 update; actual native x86_64 ABI selection, pulled digest, PID/resumed/scoped runtime log and rendered welcome observation",
    "Guarded physical main16-to17 update; pulled exact digest, certificate, firstInstallTime and spare package preservation; current-PID runtime observation",
    "Source-only docs snapshot memory refresh/plain/base coverage and known-secret scan"
  ],
  "checks": [
    {
      "category": "16kb-device",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "upgrade",
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

Exact normal16 ARM64-only bytes installed on the16KB x86 emulator, but later runtime observation proved a crash: libflutter.so architecture EM_AARCH64(183) instead of EM_X86_64(62). The advertised ARM64 ABI/native bridge was insufficient. Activity launch acknowledgment was not counted as runtime acceptance. This establishes architecture mismatch, not a physical tablet or page-size defect.

Normal17 includes native ARM64 and x86_64 libraries in **one APK**. It runs natively as x86_64 on the16KB environment, remains resumed/running with no observed current-process fatal/loader error and renders the real signed-out Google welcome. The exact same APK installs and runs as ARM64 on the4KB tablet. Both installed byte digests match `626b8084ac4894bdebaa8d9c05e3d385f291ead28a62ba9eafa114bf78bbe3c7`; production certificate/nondebuggable/ZIP/ELF checks pass. Both in-place updates preserve firstInstallTime; tablet account/data and spare .usbtest are retained. No owner screenshot, logout, financial seed or data clear.

## Evidence

[Sanitized artifact/runtime/source results](QA-014-CANDIDATE17-results.json). Frozen source hashes reproduce the checked main16 runtime inputs, including the final feedback guard. QA-030 UI edits began while the initial root17 package was building, so its successful Flutter exit was rejected for source drift and nothing installed. Frozen signing initially failed closed without the ignored private config; protected existing signing access corrected it. An unnecessary overlapping second private snapshot was started before observing the first completion; both were polled terminal, and only the final stable snapshot artifact above was selected/installed after signature/source/byte checks. The earlier successful digest is retained in results and was not installed. No build/observation timeout was treated as proof of termination.

The current main16 source previously passed826 host tests and4 native notification checks. No new Dart/native behavior changed for17; those are same-source historical regressions, separate from the actual17 startup/runtime observations. New full-screen-form work is deliberately outside this artifact and remains owned by QA-030, which was notified of final17 and the next-version18 floor.

## Limits and next action

The16KB run is native x86_64 emulator; physical ARM64 hardware remains4KB. Native ARM64-on16KB hardware, every release17 financial/lifecycle journey, fresh Google browser login and a clean independently reviewed final candidate remain unverified. Real reminder warm/cold checks are in [QA-027 native evidence](VER-QA-027-NATIVE-INTENTS.md); do not relabel them as release17 checks. No backend cutover, scheduler activation, public release or iOS runtime. Preserve current source and task ownership; any future APK needs its own digest/candidate checks and a version above17.
