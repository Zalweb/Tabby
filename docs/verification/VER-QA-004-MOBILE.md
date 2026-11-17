# QA-004 — Payment refresh, route/session isolation and accessible receipts

```json verification-metadata
{
  "id": "VER-QA-004-MOBILE",
  "task_ids": [
    "QA-004",
    "PAY-001",
    "SEC-004"
  ],
  "timestamp": "2026-11-13T18:09:00.748+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Codex root / Windows; Flutter3.47.8/Dart3.13.7; explicit Riverpod/storage/tab-loader fixtures. Android/iOS shared logic and widgets only; no connected Android transport, Xcode/iOS runtime or remote data writes.",
  "commands": [
    "git status --short --branch; git rev-parse HEAD",
    "flutter test --no-pub --reporter expanded test/features/payment_decisions_test.dart",
    "flutter test --no-pub --reporter expanded test/features/receipt_revisions_test.dart",
    "flutter test --no-pub --reporter expanded test/features/payment_decisions_test.dart test/features/due_reminders_test.dart test/features/sync_diagnostics_test.dart test/features/session_scope_test.dart test/features/friend_requests_test.dart test/features/history_rendering_test.dart test/features/picker_recovery_draft_test.dart",
    "flutter test --no-pub --reporter expanded test/features/payment_decisions_test.dart test/features/receipt_revisions_test.dart test/features/history_rendering_test.dart test/features/expense_revision_projection_test.dart",
    "flutter test --no-pub --reporter expanded",
    "dart analyze lib test integration_test",
    "flutter build apk --debug --no-pub --dart-define=TABBY_USB_TEST=true",
    "adb devices -l; adb mdns services",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs; node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0; git diff --check"
  ],
  "checks": [
    {
      "category": "focused-regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "regression",
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
      "category": "integration",
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

This continuation preserves the whole mobile production-readiness goal. Prior QA-003 progress is retained; current work is a new scoped batch, not completion of all release gates. The branch/base remain unchanged and dirty. Existing cloud/device/native packaging changes and earlier receipt/iOS repairs were preserved.

### Reproduced defects and repairs

| Finding | Reproduction / root cause | Repair and observed verification |
|---|---|---|
| Same-session refresh rolls back a confirmed payment display | Two delayed refreshes completed out of order; the older pending snapshot replaced the newer confirmed snapshot/balance. A refresh begun before an acknowledged payment could also replace its result afterward. Session guards alone could not distinguish these reads. | Each ledger load has a revision. Superseded results cannot publish state, continue subsequent cache/alarm writes or report refreshed success. Successful payment decisions/reset invalidate older snapshots. The default repository transport is unchanged; an injectable tab-loader port provides deterministic delay tests. Both reproductions fail before repair and pass after it. |
| Stale decision completion during persistence | Changing accounts while each tabs/activities/reminders write was paused let decidePayment finish normally, despite its earlier RPC session check. UI could report obsolete success. | Recheck the initiating session after each persistence/alarm await and throw on obsolescence. Three independent pause-point regressions pass, with no cache appearing under the new account. Existing payment IDs, amounts, submission counts and server confirmation authority stay intact. |
| Wrong route dismissed after asynchronous confirmation | Open a dialog above the pending payment sheet, then complete confirmation: Navigator.pop dismissed the new dialog and retained the old sheet. | Capture the exact owning route/navigator and session before awaiting. Pop only if that route is current; otherwise remove that specific active route. The newer dialog remains and the payment sheet is gone. Reminder completion follows the same ownership/session rule. |
| Financial sheets survive account change | Entry/payment details, receipt preview above shared media, and reminder sheets retained the old account's financial content. | Attach the existing session-generation AccountDraftGuard to details, shared media, receipt preview, reminders and group obligations. Regression tests assert dismissal, including stacked routes and preservation of the underlying group page in a synthetic session fixture. Receipt external-open callbacks discard stale URL/launch acknowledgments after awaits. No authorization policy is weakened. |
| Receipt panel overflows at800x600 | The new stacked-media regression reproduced a13-pixel vertical overflow in fixed-height receipt content. | Make the content panel scrollable. Keep close/actions accessible and preserve original receipt bytes. |
| Small-phone/200%-text detail layout overflows | At360x640 and text scale2, the unbounded summary header overflowed vertically by356 pixels. After bounding it, the history heading/record-count row exposed a342-pixel horizontal overflow. | Bound the summary header to70% of available body height with independent scrolling, keep the ledger lazy/paged, wrap its history heading/controls and scroll receipt content. The test asserts no exception on the tab page, media list and preview, then closes the preview. It now passes at the original size/text settings. Text scale and assertions were not reduced. |

### Verification history and scope

- Initial payment suite:6 passed,5 failed. Expanded delayed-refresh reproduction:6 passed,7 failed. All named defects above remained visible in logs before repair.
- First repaired payment suite:13/13; neighboring reminder/cache/session/history/picker suites59/59 passed.
- Stacked-media reproduction also exposed the layout failure. Large-text checks located the distinct tab-header then history-row overflows. Temporary error diagnostics were removed after fixing the actual layouts; assertions remain.
- First full checkpoint:667 passes,1 failure. The failure was the correction-history test using the first Scrollable, which now refers to the scrollable header. Scoped that interaction to the ledger ListView; retained its actual correction action/audit-reason assertions. The paged-history test received the same explicit ledger target and still verifies delayed older-record loading.
- Initial analyzer found two new brace infos and a test super-parameter suggestion; corrected them. Final `dart analyze lib test integration_test` reports no issues.
- Final four-file focused integration suite passes28/28, including payment routes, retained receipt images, small-phone large text, paged history and correction UI.
- Full regression and final debug packaging were started after those repairs. Their observed terminal results are appended below before handoff; they are not inferred from targeted checks.
- Current ADB device and mDNS inventories are empty. No native device or remote account is exercised by these widget/storage fixtures. Existing SQL/HTTP acceptance remains the explicitly bounded earlier [QA-003 evidence](VER-QA-003-MOBILE.md); no SQL, migrations, RPC wire contract or worker source changed in this batch.

## Evidence

[Payment regression](../../test/features/payment_decisions_test.dart), [receipt/privacy/accessibility regression](../../test/features/receipt_revisions_test.dart), [history paging](../../test/features/history_rendering_test.dart) and [correction visibility](../../test/features/expense_revision_projection_test.dart). Source: [provider](../../lib/features/tabs/application/tabby_providers.dart), [decision widget](../../lib/features/tabs/presentation/payment_decision_actions.dart), [tab detail/media sheets](../../lib/features/tabs/presentation/tab_detail_screen.dart).

Ignored `.dart_tool/readiness/qa004-*` logs retain failure reproductions, diagnostics and superseding results. The dated source/result manifest added at handoff identifies final input hashes and actual results without private accounts/images or credentials. QA-003 artifacts remain historical and are not overwritten. SDK invocations use the same direct Flutter snapshot command recorded there.

## Limits and next action

This is local source/UI logic acceptance. Independent integration review, actual Android/iOS account lifecycle, native receipt picker/media behavior, provider/full platform acceptance and all exact signed release gates remain open. Continue the active feature/logic audit; production remains NO-GO. No deployment, endpoint switch, remote financial/account mutation, signing, publication, signup/scheduler/M2 activation or messages occurred.

### 2026-11-13T18:09:00.748+08:00 — Final terminal results

Full Flutter670/670 passed (exit0); final Dart analysis reports no issues (exit0); isolated debug APK packaging passed23.4s (exit0), with actual com.zalweb.tabby.usbtest badging. Final [source/result manifest](QA-004-results.json) retains454 source hashes, log hashes and debug-only artifact digest. Backend/migration/worker sources match the earlier QA-003 manifest and were not rerun or deployed. Current goal remains active; native/provider/review/release gates stay open.
