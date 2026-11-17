# VER-PRO-002 — Real profile photo drafts and private avatar objects

```json verification-metadata
{
  "id": "VER-PRO-002",
  "task_ids": [
    "PRO-002"
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
      "category": "android-build",
      "outcome": "passed"
    },
    {
      "category": "backend-authorization",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T12:38:25.993Z",
  "tested_commit": "cf33b1b36e5f01c6d89c108c0a9625c6b5f4cae9",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8; synthetic PNG/identities, real Flutter image codecs/widgets with explicit picker/storage/transport fixtures. Native PostgreSQL17.11 and PGlite selected migrations through20261101000009; authenticated/anon Storage policy execution. No real user photos, cloud Storage HTTP or device.",
  "commands": [
    "flutter test test/features/profile_avatar_test.dart test/features/interactive_features_test.dart test/features/e2e_all_screens_buttons_test.dart",
    "flutter test",
    "dart analyze --fatal-infos",
    "flutter build apk --debug",
    "node scripts/test-money-commands.cjs",
    "node scripts/test-backend-native.cjs",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base cf33b1b",
    "git diff --check"
  ]
}
```

## Expected and actual results

Final full Flutter suite passed489/489; Dart analysis clean; Android debug APK built. Thirteen new model/widget regressions cover retained image/path restart, uncertain-response same-photo replay, cancellation, upload failure before profile write, late account/session results, account isolation/corrupt draft retention, failed storage writes, older cleanup preserving newer selections, acknowledged preset changes, actual image preparation/dimension bounds, selected-photo retry/acknowledgment, download retry and clearing a previous image during reference changes. Targeted avatar/existing-interaction suite previously passed32/32 before adding the final download-retry regression. Native PostgreSQL17.11 and PGlite pass actual Storage RLS owner insert, malformed/foreign path denial, immutable objects, accepted-friend/current-only and active-peer reads, archived/outsider/anon denial and missing/foreign photo-reference rejection; financial/profile/QR/push/concurrency suites remain passing.

## Evidence

[Avatar regressions](../../test/features/profile_avatar_test.dart), [durable draft/image preparation](../../lib/features/profile/application/profile_avatar_draft.dart), [picker/save sheet](../../lib/features/profile/presentation/profile_avatar_sheet.dart), [authenticated renderer](../../lib/features/profile/presentation/profile_avatar.dart), [private Storage migration](../../supabase/migrations/20261101000009_profile_avatars.sql), [role-based SQL contracts](../../scripts/test-profile-avatars.cjs). Source images are limited to10MB/24million pixels, canonical longest edge512pixels, retained/upload PNG limit2MB. Per-owner storage barriers and conditional cleanup avoid older acknowledged drafts erasing a newer selection.

## Limits and next action

Physical Android and live Supabase acceptance remain open. API/Storage/RLS fixtures are a selected migration inventory, not the full hosted environment. Pending photo survives only after the picker returns and owned bytes persist; picker process death before return still needs AND-003. Old unreferenced uploaded objects are not automatically deleted. No credentials/private photos, deployment or publication.
