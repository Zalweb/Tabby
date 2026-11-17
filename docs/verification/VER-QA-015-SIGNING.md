# QA-015 — Private production signing and Android staging upgrade rehearsal

```json verification-metadata
{
  "id": "VER-QA-015-SIGNING",
  "task_ids": [
    "QA-015"
  ],
  "timestamp": "2026-11-14T14:20:41.074+08:00",
  "tested_commit": "734d80093c1a340c87eab1b2b3b5303372e63319",
  "dirty_tree": true,
  "environment": "Windows restricted private signing; new-key release APKs on API36/16KB x86_64 emulator; live SDK Auth/Realtime on paired Lenovo TB321FU/API36/4KB isolated package",
  "commands": [
    "flutter build apk --release --dart-define-from-file=<ignored public-client config>",
    "flutter build apk --release --build-number=6 --dart-define-from-file=<ignored public-client config>",
    "node scripts/verify-android-artifact.cjs <private staging APK and exact certificate options>",
    "node scripts/usb-test.cjs --suite live --transport wifi --device <advertised TLS endpoint> --live-config .env.usb-live.json",
    "adb -s emulator-5580 install -r <verified private signed staging APK>"
  ],
  "checks": [
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "upgrade",
      "outcome": "unverified"
    },
    {
      "category": "live-backend",
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

Created the explicitly approved new RSA4096 production identity outside Git, with current-user/SYSTEM-only ACLs and ignored android/key.properties. Both private release APKs are nondebuggable, signed by the new identity, and pass ZIP/ELF LOAD/RELRO16KB validation. The verifier now rejects writable data in a RELRO trailing16KB page, with five regression cases. Release/debug build transitions regenerate mode-specific plugin registration. Real synthetic email login on signed v5 reached the expected profile-completion gate; same-key v5→v6 install-r preserved application appId, Auth session and onboarding state, observed again at the same profile gate. Physical live SDK Auth/RLS/Realtime passed with RPC acknowledgment/readback and verified profile restoration.

Private v1.0.4+5 SHA51678db0c7dda3af734f152fe995a2ffba4e3a1df18ccc91b52a4cc3282864fd; +6 SHA531a16c6e83e9a5d806e6aa47c3d28e66ab631d0a06d775d90743b0e4062febc. Certificate SHA2564867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a. First physical Realtime run timed out, retained as failed; standalone real SDK diagnostic and subsequent physical run2026-11-14T04-37-05-464Z passed. Initial release --no-pub build failed stale dev-plugin registration; normal dependency/plugin regeneration fixed it. No production app defect or first-timeout root cause inferred.

## Evidence

[Sanitized current results, artifacts, source delta and log digests](QA-018-results.json). Tested source is base 734d80093c1a340c87eab1b2b3b5303372e63319 plus the recorded dirty-tree delta. Private local signing and emulator installation only; physical installs limited to .usbtest. No APK/key uploaded, public release, personal production install replacement or default endpoint change.

## Limits and next action

New key cannot update either prior debug-signed installation in place. Existing personal installation/data preserved. Signed financial queued-data upgrade, legacy data transition, ARM64 runtime, Google/FCM/provider acceptance, exact final candidate and integration review remain open. Private staging builds omit Firebase and use Azure client overrides, not a production endpoint cutover.

Back up the external signing folder securely. Finish provider configuration and signed financial-data/legacy transition acceptance before selecting a final release artifact.
