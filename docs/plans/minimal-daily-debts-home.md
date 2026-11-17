# Minimal daily-debt interface implementation plan

Date: 2026-11-17. User selected the supplied mascot-led Home reference and asks that the other pages retain useful real features with minimal clutter. This includes the preceding request to fix the square Appearance mode-selection highlight.

## Selected design and boundaries

Home becomes: compact greeting/notifications → one cream/amber net-position card with large native amount and existing notebook mascot → meaningful tab-clearance summary → activity-period selector → confirmed Received/Paid strip → due reminders → recent activity. Remove duplicate balance/progress blocks and the promotional illustration. A prominent add action opens the real creation flow alongside the three existing Home/Tabs/Profile destinations. Do not add a nonfunctional Stats destination from the reference. Keep charcoal-on-amber controls, theme-aware dark surfaces and minimal functional icons; no emoji greeting or baked-in UI text.

The existing domain totals continue to govern outstanding balances. A zero aggregate does not mean all settled when opposite group obligations remain. Tab-clearance progress evaluates each tab's actual payables/receivables and unresolved legacy-group information. Received/Paid are filtered **confirmed payment entries** with explicit payer/recipient, deduplicated by entry ID, never inferred from an expense amount or activity description. Unknown legacy parties are excluded with an honest notice. When both payables and receivables exist, the hero shows both alongside the net position. Filters affect payment/activity history, not current obligations or due reminders.

Builder check clarified the implementation choices: payment windows use LedgerEntry.date (recorded submission date, since no confirmation timestamp exists in the model), disclosed in the UI; tab clearance means clear **for the current user**, even when other group members still owe one another. These choices do not extend backend contracts.

Secondary pages: simplify Profile's static PHP/English information rows and duplicate provider advertising; keep receiving methods, security, friends/Tabby-ID connection, group creation where needed, notifications, appearance, sync/retry, privacy/export, support, version and logout functional. Tabs and details retain actual creation, search, group/settlement/history features; remove decorative duplication rather than working capability. Do not delete real features merely because reference mockups omit them. Do not modify provider/model/wire/auth/notification contracts.

Appearance uses two padded rounded choices with a clear selected border/radio, safe insets, scrollable large-text content, readable light/dark colors and saved-state/busy/failure behavior. Reuse this choice treatment wherever that existing helper is consumed.

Approach: composing from real shared state and focused presentation widgets preserves financial truth and reusable warm tokens. A cosmetic copy of mock figures/progress/Stats would be misleading; keeping the current stacked duplicate KPI blocks would not satisfy the user's selected hierarchy. Existing raster mascot assets are sufficient; native layout supplies cards, shapes, text and controls.

## Execution

- [x] Claim QA-028/read set and snapshot affected sources; coordinate with QA-027's separate notification wiring and .usbtest session.
- [x] Implement/read-only-test the Home payment/tab summary; rebuild Home around the selected hierarchy and existing action handlers.
- [x] Add the real create action to navigation; round/pad mode choices and simplify non-actionable secondary-page clutter without losing working entry points.
- [x] Update design authority and reusable skill; verify persistence/failure, group offset/confirmed-payment boundaries, empty/populated light/dark/phone/tablet/200% states and action routing.
- [x] Run relevant/full regression, analysis and synthetic previews; coordinate any private tablet update after a stable candidate. Preserve main data/session and the concurrently used .usbtest package. Record exact evidence, remaining gates and final memory/base checks.


2026-11-17T09:40:07.033Z — Sequence executed; [verification/remaining gates](../verification/VER-QA-028-DAILY-HOME.md).
