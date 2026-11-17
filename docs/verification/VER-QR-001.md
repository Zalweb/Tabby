# VER-QR-001 — Receiving QR validation

```json verification-metadata
{
  "id": "VER-QR-001",
  "task_ids": [
    "QR-001"
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
      "category": "backend-authorization",
      "outcome": "unverified"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-10-31T18:48:41.212Z",
  "tested_commit": "65a155a335b1bb1ae5f2aece4cc2320710760ac3",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8; zxing2 0.2.4 pure Dart decoder; Flutter image codec tests; injected gallery/repository boundaries and synthetic QR payloads.",
  "commands": [
    "flutter pub add zxing2:^0.2.4",
    "dart analyze --fatal-infos",
    "flutter test test/core/qr_image_validator_test.dart test/features/interactive_features_test.dart",
    "flutter test",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Dart analysis clean; focused QR/interactive suite passed 14/14; full Flutter suite passed 345/345. Six new regressions exercise actual QR encoding/decoding, corrupt/oversize/patterned rejection, numeric account-code rejection, setup without generator, picker failure and invalid upload feedback.

## Evidence

[QR regressions](../../test/core/qr_image_validator_test.dart) decode actual synthetic PNGs rather than checking finder patterns. [Validator](../../lib/core/services/qr_image_validator.dart) bounds bytes/pixels, disposes its native decoder images and checks crop equivalence. Decoder API reviewed against [upstream documentation](https://github.com/xvrh/zxing-dart). No real user account or financial payload used.

## Limits and next action

No wallet provider compatibility, Android gallery, actual payments, deployed storage or release approval. A readable QR is not an ownership/financial verification. Legacy methods are not silently rewritten.
