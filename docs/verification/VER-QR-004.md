# VER-QR-004 — Receiving QR freshness and bounded recovery

```json verification-metadata
{
  "id": "VER-QR-004",
  "task_ids": [
    "QR-004"
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
  "timestamp": "2026-10-31T19:06:34.904Z",
  "tested_commit": "0661e9fd3edc966631502d80b4f0a282da1f72ee",
  "dirty_tree": true,
  "environment": "Windows Flutter 3.47.8 with synthetic method repositories, failed test-network images and explicit session/lifecycle inputs. No actual signed HTTP URL expiry or device.",
  "commands": [
    "dart analyze --fatal-infos",
    "flutter test test/features/payment_method_freshness_test.dart test/features/payment_method_lifecycle_test.dart test/core/qr_image_validator_test.dart test/features/interactive_features_test.dart",
    "flutter test",
    "node scripts/check-project-memory.cjs --write",
    "git diff --check"
  ]
}
```

## Expected and actual results

Dart analysis clean; focused QR/freshness/lifecycle/interactive tests passed 28/28; full Flutter suite passed 359/359. Seven new regressions cover out-of-order reads, refresh error versus empty list, bounded signing/network-image retry, removal, stale-session discard and resume/explicit reload.

## Evidence

[Freshness regressions](../../test/features/payment_method_freshness_test.dart) exercise actual provider/widget recovery. [Receiving image](../../lib/features/payment_methods/presentation/receiving_qr_image.dart) preserves a per-method automatic retry guard, refreshes authorization and discards old-session results. Native SQL method access/lifecycle acceptance remains in VER-QR-002/003; no backend changes in this batch.

## Limits and next action

Mock lifecycle/network boundaries do not establish Android resume, deployed policies or actual HTTP expiry. No deployment/publication or release approval.
