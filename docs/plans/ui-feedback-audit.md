# UI feedback audit and balanced navigation

2026-11-17. User requests finding/fixing UI bugs, especially errors/notifications behind pages or Add forms, and moving Add to the lower-right to restore an evenly centered three-item navbar. Use installed systematic-debugging, UI/UX Pro Max and Tabby design guidance. External skill discovery verified UI/UX Pro Max's Flutter/UI-review scope; no additional installation required.

## Root cause and selected repair

Bottom-sheet routes usually have no Scaffold. Calls to ScaffoldMessenger.of inside those routes reach the background page Scaffold; their snackbars can exist in the widget tree while being visually covered. Add's validation, receipt/draft feedback and some nested settings sheets use this pattern. Receiving/payment editors already have inline save errors and should retain those guards. Root realtime banners also use a page snackbar and need to target the current sheet when one is active.

Use a small route-scoped feedback host around application bottom-sheet builders, with a visible dismissible live-region message above scrollable sheet content. A shared feedback facade chooses that local host, otherwise delegates to the existing page messenger. Nested sheets receive their own host; disposed/noncurrent routes cannot receive global notifications. Keep inline errors and business callbacks unchanged. Retain the original safe-inset, draft/session, barrier/drag/back and keyboard contracts. Verify actual hit testing/paint bounds rather than treating find.text as visibility evidence.

Move the actual Add action to Scaffold.floatingActionButton at the lower-right on Home/My Tabs, clear of the three evenly spaced Home/My Tabs/Profile nav items. Omit Add on Profile. Keep one stable key/action path and sufficient scrolling space so the button cannot permanently cover the last list action. It must disappear behind open sheets rather than intercept their actions.

## Execution/checks

- [x] Claim QA-029 and snapshot affected source; preserve current dirty tree and separately owned notification delivery/readiness work.
- [x] Reproduce covered Add validation and a nested-sheet feedback scenario; inspect shared overlay behavior and current inline boundaries.
- [x] Add scoped feedback host/facade and wrap applicable bottom-sheet builders; direct existing feedback to the nearest active route without changing persistence/payment logic.
- [x] Move Add to lower-right and test nav centers, page availability and last-row reachability.
- [x] Exercise validation/save/picker failures and realtime notification visibility over a sheet, nested disposal, keyboard,200% text and light/dark. Run focused/full tests, analysis, previews and the isolated tablet UI suite.
- [x] Update design/skill/task evidence, check source/artifact identity and install the private same-key tablet update if available. Refresh plain/base project memory; do not claim public release/independent review.

2026-11-17T10:17:39.188Z ? Additional routing invariant: a current local route in an inactive StatefulShell branch is still hidden. Feedback targets require current route and enabled TickerMode, in the same ScaffoldMessenger. Seven behavioral regressions cover this, Add validation, nested ownership, post-pop success, stale sessions and both themes with keyboard/200% text. The initially successful five-case device run preceded this final visibility predicate. Root Android builds/device control are yielded to QA-027 until its cold-tap/update is terminal; reject moving-source packages and adopt only exact current source hashes.

2026-11-17T10:27:13.541Z - Execution checks terminal; independent review remains a task gate. See final verification/results.
