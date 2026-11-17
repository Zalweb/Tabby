# QA-011 — Account-bound receiving-method views and actions

```json verification-metadata
{
  "id": "VER-QA-011-RECEIVING",
  "task_ids": [
    "QA-011",
    "QR-004",
    "QR-006",
    "SEC-004",
    "QA-001",
    "REL-001"
  ],
  "timestamp": "2026-11-14T01:22:33.161+08:00",
  "tested_commit": "2ac41340bd879f3bbe8e2a50e1e1a63f680947e5",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8/Dart3.13.7; synthetic Flutter widget/provider/account/clipboard fixtures, blocked example.invalid images. No real account or device/wallet/Storage boundary.",
  "commands": [
    "flutter test --no-pub --reporter expanded test/features/receiving_session_scope_test.dart",
    "flutter test --no-pub --reporter expanded test/features/receiving_session_scope_test.dart test/features/receiving_qr_export_test.dart test/features/payment_method_freshness_test.dart test/features/payment_method_lifecycle_test.dart test/features/session_scope_test.dart test/features/friend_profile_test.dart",
    "flutter test --no-pub --reporter expanded",
    "dart analyze --fatal-infos lib test integration_test",
    "flutter build apk --debug --no-pub --dart-define=TABBY_USB_TEST=true",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs; node scripts/check-project-memory.cjs --base 2ac41340bd879f3bbe8e2a50e1e1a63f680947e5; git diff --check"
  ],
  "checks": [
    {
      "category": "focused-regression",
      "outcome": "passed"
    },
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "android-debug-build",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "ios-device",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "real-storage-wallet",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

| Finding | Before / actual reproduction | Implemented / final evidence |
|---|---|---|
| Friend/payment sheets retain old private details | Both remain visible after another account or same-account relogin. | Bind the initiating stamp and existing exact-route guard. Both transitions dismiss each private sheet and preserve its underlying page. |
| Fullscreen and inline QR retain old session content | QR dialog/pixels remain after either transition; another dialog above it hides the stale route without disposing it. | Clear cached image state on revision; block old refresh/fullscreen/export and guard the exact fullscreen route. Four QR cases preserve a newer unrelated dialog while removing the old QR and inline private label. Existing immutable image bytes/authorization rules unchanged. |
| Cached copy callback writes old details | Invoke the rendered callback after revision but before rebuild: old account details reach Clipboard.setData and success acknowledgment appears. | Capture card lifetime scope, clear old state, reject before native dispatch, and recheck after awaited clipboard acknowledgment. Both transitions reject the cached callback. Two delayed success/error controls suppress obsolete snackbar after an already initiated authorized copy. |
| Clipboard failure reports false success/unhandled error | MethodChannel throws PlatformException; unawaited setData escapes and success text is shown. | Await/catch with scoped actionable error. Normal success/error controls pass. No claim that a launched external action can be rolled back after dispatch. |
| Provider cache outlives session before profile update | Keep current profile fixture unchanged, populate default family cache from offline legacy data, change account/relogin. Same cached method remains. | Invalidate family on session revision with disposal cleanup. Both cases synchronously read empty/loading new state. This fixture isolates cache lifetime; it does not establish server visibility or a production legacy fallback. |
| Owner list/preview and cached actions survive transition | Owner list and nested preview remain across both transitions. Cached prefer/delete/edit/preview callbacks still invoke mutation or open old owner data. | Bind owner sheet/preview routes and guard all owner continuations, editor saves, resume setup and refresh before/after awaits. Four route plus four cached-action cases pass; obsolete callbacks issue no mutation/open. Server commands/consent unchanged. |

Final54/54 neighboring checks contain24 new account/action/provider cases and30 existing image freshness, export, method lifecycle, session and friend-profile cases. Full736/736 Flutter passes; analysis reports no issues; isolated debug APK packages in20.5s, actual com.zalweb.tabby.usbtest1.0.4+5. No native runtime result is inferred.

### Failure history

The first new test had an ambiguous PaymentMethod import; narrowed models import, then observed0/10 product failures. Added clipboard error/positive control:1/12 original-source outcome. Provider cache2/2, owner list/preview4/4 and owner callbacks4/4 were reproduced before their fixes. Two late clipboard controls were added after the first repair. A source patch anchor mismatch applied no changes; corrected the exact anchor. Initial neighbor43/44 failed only because the stale-QR test expected generic retry copy. Retained its no-image assertion and require reopen/no Retry QR for an obsolete account. Five analyzer context/brace infos fixed. Initial full728 passed before the eight owner cases/fix; final736 is the superseding source. No assertions were disabled.

## Evidence

[Receiving regression](../../test/features/receiving_session_scope_test.dart), [stale URL regression](../../test/features/payment_method_freshness_test.dart), [session cache](../../lib/features/payment_methods/application/payment_methods_provider.dart), [friend sheet](../../lib/features/payment_methods/presentation/friend_receiving_methods_sheet.dart), [payment/card](../../lib/features/payment_methods/presentation/payment_method_payment_sheet.dart), [owner management](../../lib/features/payment_methods/presentation/payment_methods_sheet.dart), [QR view](../../lib/features/payment_methods/presentation/receiving_qr_image.dart), [final source/result/log hashes](QA-011-results.json). 461 source hashes and debug artifact digest recorded. Ignored qa011-* logs retain failure and final checkpoints; the APK is retained under ignored qa011-debug.apk.

The authorized prior local checkpoint is2ac41340bd879f3bbe8e2a50e1e1a63f680947e5; this is its focused subsequent patch. Backend/migrations/native config/tooling match QA-008 and committed source. SQL52-migration acceptance remains [QA-007 scope](VER-QA-007-SOCIAL-CONCURRENCY.md). No source backend writes or rollout activation.

## Limits and next action

Production NO-GO. Actual wallet/native clipboard/Storage/Android/iOS lifecycle, independent integration review and exact clean signed candidate/upgrade/provider/16KB gates remain open. QA-009 transport is still unavailable; advertisement does not prove a connected device. Validate shared memory and staged tree, make the authorized local fix commit, then continue remaining financial overlays/session paths. No push, deployment, endpoint switch, actual account mutation, publication or messages.
