# home-and-notifications implementation plan

## Mobile integration checkpoint — 2026-11-13T16:25:00+08:00

iOS local notification presentation and response forwarding require the UserNotifications delegate to be assigned to FlutterAppDelegate before launch completes. [QA-003](../progress/tasks/QA-003.md) repairs this missing native integration and adds a configuration regression. This establishes source configuration only; foreground/background/cold-tap delivery still needs an iPhone run. Android remote FCM integration and local scheduling remain separate from iOS remote delivery, which is not wired; do not describe this repair as APNs/FCM support.

## Purpose and current state

Truthful balances, correct filters, obligation-based reminders and reliable delivery. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Mobile agent**.

## Target behavior and contracts

Derive reminders from current outstanding obligations. Respect account-scoped preferences at scheduling and delivery. Server acceptance means sent, not delivered. Background push requires an account-bound device token; logout revokes token association and local alarms. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [HOME-001](../progress/tasks/HOME-001.md) — Dashboard labels and monthly filter misrepresent data | P2 | Boundary dates filter correctly and KPIs match outstanding obligations rather than spending. |
| [HOME-002](../progress/tasks/HOME-002.md) — Settled reminders return after refresh | P1 | Settle dated debt, refresh/restart/reconnect: no reminder or overdue alert returns. |
| [HOME-003](../progress/tasks/HOME-003.md) — Notification preferences and permissions are disconnected | P1 | Fresh permission allow/deny, disable preferences and logout each produce the expected alert behavior. |
| [HOME-004](../progress/tasks/HOME-004.md) — Reminder sent state and closed-app delivery are unreliable | P2 | Offline/rejected sends do not claim sent; closed app receives accepted reminders and tap opens authorized target. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Truthful dashboard totals and activity periods checkpoint 2026-10-31T19:35:55.320Z

KPI amounts are current outstanding obligations, independent of activity period. Group obligations preserve each direct member pair; opposite pairs do not cancel in payable/receivable totals. Activity windows include [now-duration, now] for 24 hours/7 days and [local month start, now] for calendar month; future rows are excluded. Existing disputed/cancelled expenses do not contribute to balances. Legacy group data is retained and flagged rather than silently inferred or rewritten.

See [verification](../verification/VER-HOME-001.md). No deployment; environment-specific limits remain open.

## Obligation-based due reminders checkpoint 2026-11-01T03:59:51.430Z

Reminders are a derived view, never merged independently from stale cache. Only remaining direct obligations produce reminders. For a running pair balance without per-bill payment links, opposing expenses/confirmed payments cover oldest due bills first, then undated bills; this allocates reminder display only and never rewrites financial history. Each reminder names the actual typed counterparty and source entry. Zero group net does not imply all member pairs are settled.

See [verification](../verification/VER-HOME-002.md). No deployment; environment-specific limits remain open.

## Account-scoped notification lifecycle checkpoint 2026-11-01T04:18:45.687Z

Device alerts require explicit account-scoped opt-in plus current OS permission. Category/master switches gate both foreground banners and native notifications; disabled alerts do not erase in-app history. Account/session changes invalidate queued work immediately and serialize OS cancellation after in-flight writes. Persistent IDs resolve collisions explicitly; acknowledged immediate alerts deduplicate by event ID, while scheduled alerts additionally reconcile actual OS pending requests. Remote acceptance/delivery remains a separate HOME-004 contract.

See [verification](../verification/VER-HOME-003.md). No deployment; environment-specific limits remain open.

## Server-acknowledged reminder submissions checkpoint 2026-11-01T04:28:06.150Z

Reminder acceptance is an atomic idempotent recipient-inbox write with a matching audit. Display waiting while the request is unresolved; display acceptance only after the original session receives its server UUID. Persist/reuse the same operation ID for an ambiguous response, reject conflicting payloads, and never use direct INSERT as a fallback. Server eligibility is a current sender-creditor/recipient-debtor pair on an active tab, including groups; new sends are limited to one per sender/tab/recipient pair per six hours. A new operation inside that window returns HTTP 429 with PostgREST code `PT429`, message `Reminder rate limit exceeded`, and no notification, activity or operation row. Exact replay of the accepted operation remains HTTP 200/idempotent and is checked before throttling; a changed payload remains HTTP 400. The server serializes sender requests so concurrent distinct operation IDs produce at most one accepted notification. Acceptance is not remote delivery/read evidence.

See [verification](../verification/VER-HOME-004.md). No deployment; environment-specific limits remain open.

## Account-bound Android background reminders checkpoint 2026-11-01T04:46:10.723Z

Background reminders require explicit permitted account-scoped opt-in and an acknowledged installation/session binding. The private queue rechecks the current token hash, binding, membership and pair debt before leasing; retries use bounded backoff and stale leases cannot finish new attempts. The backend worker uses backend-only OAuth and sends no automatic notification payload, names or amounts. Android validates account/binding before generic private display. Cold/warm taps wait for auth/router startup and read current membership before opening a fixed route. Firebase/provider acceptance never means delivered/read. See project/BACKGROUND_REMINDERS.md for setup and unverified rollout gates.

See [verification](../verification/VER-HOME-005.md). No deployment; environment-specific limits remain open.


## App-wide warm presentation — 2026-11-17T08:16:51.570Z

The current user directive/DEC-014 extends welcome/introduction cream, amber and charcoal across this area's screens and overlays, with matching dark mode. [Current design authority](../project/DESIGN.md) and [QA-026](../progress/tasks/QA-026.md) supersede former mint/emerald presentation only. Existing behavior, financial meaning, native QR/image colors and session/durable-save guards remain. Verification must distinguish UI fixtures from actual provider/backend/device acceptance.


2026-11-17T09:27:12.728Z — User-selected minimal Home hierarchy is tracked by [QA-028](../progress/tasks/QA-028.md). One net/mascot hero and personal clearance replace duplicate KPI/progress/promo blocks; confirmed payment totals use explicit parties and recorded dates, with period filter independent of outstanding obligations. Preserve reminder delivery acceptance and session/authorization contracts. [Design](../plans/minimal-daily-debts-home.md).


## Notification target readiness — 2026-11-17T09:35:42.795Z

Server membership is required before a remote tap loads its target. Await a current-account ledger refresh and an exact tab model before routing; transient load failure retains the pending tap, and account/newer-tap changes invalidate navigation. Header pagination explicitly requests ascending IDs to match increasing continuation. A missing/not-yet-loaded model must not be treated as proof the authorized tab does not exist. [QA-027 evidence](../verification/VER-QA-027-NOTIFICATION-TAP.md) separates failed first physical repair from current cursor correction and pending final tap.

2026-11-17T10:06:37.311Z ? QA-029 presentation amendment: Add is a lower-right floating action on Home/My Tabs; three nav destinations are evenly centered. Realtime banners use the active sheet feedback host. Notification delivery/readiness/membership and live tap acceptance remain QA-027-owned. [UI audit plan](ui-feedback-audit.md).


## Native callback ownership — 2026-11-17T10:29:05.386Z

Android Flutter default URL handling is disabled because app_links owns OAuth and the account-bound native push channel owns reminder taps. PendingIntent URI remains unique identity, never an arbitrary navigation route. Native onNewIntent leaves payload extras pending until Dart requests initialTap after installing its listener; consume under the current binding, then wait for authenticated server authorization and exact target data before navigation. [Actual warm/cold evidence](../verification/VER-QA-027-NATIVE-INTENTS.md).

2026-11-17T14:30:25.234Z - QA-031 shared notebook art on Home now breathes subtly; reminders/empty states retain their actual status and shared pose mapping. No notification delivery/financial provider changes. [Mascot plan](situation-mascot-animation.md).
