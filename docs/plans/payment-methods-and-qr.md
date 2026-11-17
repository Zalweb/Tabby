# payment-methods-and-qr implementation plan

## Purpose and current state

Reusable wallet-issued QR upload, authorized access and update propagation. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Payments agent**.

## Target behavior and contracts

Owner, accepted friend or a debtor with an outstanding pair obligation can read an active method. Debt access applies within groups too. Unrelated users and anonymous users cannot read it. Stable storage references outlive short-lived signed display URLs. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [QR-001](../progress/tasks/QR-001.md) — Account-string QR is presented as a payment QR | P1 | Setup offers upload and rejects non-QR images; no generic account-number QR appears. |
| [QR-002](../progress/tasks/QR-002.md) — Debtor storage authorization may reject private QR reads | P1 | Two authenticated accounts load a permitted image; stranger/anon and guessed paths fail. |
| [QR-003](../progress/tasks/QR-003.md) — Saved QR has no edit/replacement flow | P2 | Upload failure preserves old method; successful replacement appears on another device. |
| [QR-004](../progress/tasks/QR-004.md) — Signed QR views become stale | P2 | Expire URL, reopen flow, update/remove method from another session; correct state appears. |
| [QR-005](../progress/tasks/QR-005.md) — Preferred method and removal state are wrong | P2 | Add nondefault preserves preference; remove default promotes exactly one remaining method. |
| [QR-006](../progress/tasks/QR-006.md) — QR validation, same-phone use and profile visibility are incomplete | P2 | Wallet import works on one phone; unreadable images fail; friend/debtor access matches the agreed matrix. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Receiving QR validation checkpoint 2026-10-31T18:48:41.212Z

Receiving QR images must decode before upload. Account labels remain manual text and never become generated payment QR images. Uploaded content is canonical PNG, up to 10 MB input and 24 million source pixels, decoded at at most 2048 pixels per side; crop output must preserve the decoded payload. Readability is distinct from wallet ownership and money confirmation.

See [verification](../verification/VER-QR-001.md). No deployment; environment-specific limits remain open.

## Exact-object method access checkpoint 2026-10-31T18:50:28.229Z

can_read_payment_method and can_read_payment_method_file use the current authenticated caller; object reads require an exact active method reference. Accepted friendship or a positive direct pair obligation in a shared active tab authorizes nonowners. Aggregate group balance is not an access criterion. Method removal/settlement affects new reads; already issued signed URLs retain their limited bearer lifetime.

See [verification](../verification/VER-QR-002.md). No deployment; environment-specific limits remain open.

## Atomic receiving method lifecycle checkpoint 2026-10-31T19:00:30.663Z

change_payment_method_v1 serializes all owner method metadata changes and stores actor/operation commands/results. Save uses expected_revision for edits and an already uploaded owner object; replacement never overwrites an old object. Soft removal preserves history and atomically selects one successor. Nonfinancial method revision snapshots are owner-readable and client immutable. Client acknowledgment is distinct from uncertain response failure; uncertainty retains the draft and asks for refresh.

See [verification](../verification/VER-QR-003.md). No deployment; environment-specific limits remain open.

## Receiving QR freshness and bounded recovery checkpoint 2026-10-31T19:06:34.904Z

Receiving-method views refresh on entry/resume and every five minutes while mounted. Each fetch regenerates URLs from stable paths. Failed images/signing refresh authorization once before exposing explicit retry; live empty/error results never fall back to legacy profile QR URLs. Newer load generations win. Remote changes are visible on refresh/reentry; existing bearer URLs retain their lifetime.

See [verification](../verification/VER-QR-004.md). No deployment; environment-specific limits remain open.

## Android QR export and friend profile access checkpoint 2026-10-31T19:14:45.701Z

Android save uses ACTION_CREATE_DOCUMENT through the activity-result API; only an actual completed output write reports saved. Share uses ACTION_SEND image/png with a read-only FileProvider URI scoped to receiving-qr cache and reports chooser launch, not delivery. Export reauthorizes the active method/private object and rejects old-session results. Friend profile methods are read-only and server-authorized; displaying, saving or sharing QR never confirms money.

See [verification](../verification/VER-QR-006.md). No deployment; environment-specific limits remain open.

## Profile-setup receiving-method follow-up

The AUTH-003/AUTH-004 review found a separate profile-setup editor still generated account-text QR codes despite the earlier owner-editor fix. That residual flow now uses the shared validated receiving editor. Setup explicitly stages drafts, retains stable retry IDs and reports per-item acknowledgment; GCash/Maya details require user confirmation and never derive automatically from a profile phone. This corrects the earlier broad implementation claim; wallet/device/deployed-policy checks remain unverified. See [VER-AUTH-003](../verification/VER-AUTH-003.md).

## Friendship consent boundary checkpoint 2026-11-13T18:49:13.170+08:00

Friendship creation and acceptance must use authenticated guarded RPCs; direct INSERT cannot manufacture accepted consent or unlock friend-only profile/receiving/avatar access. Additive [QA-006 repair](../verification/VER-QA-006-FRIENDSHIP.md) removes the legacy requester-only policy, qualifies declined resend and repairs acceptance notification/canonical-tab linkage. Fresh51 migrations,50→51 preserved-history upgrade and standalone snapshot pass locally. No deployed remediation or retrospective deletion is claimed; review effective deployed grants/policies and complete real-account/platform acceptance before release.

## Account-bound receiving views checkpoint 2026-11-14T01:22:33.161+08:00

Friend/payment/owner sheets, owner preview and fullscreen QR dismiss their exact initiating route after account change/relogin; inline/card cached content clears. Old refresh/copy/export/owner callbacks reject obsolete generation, and clipboard success/error follows awaited scoped acknowledgment. Provider cache invalidates on session revision before profile refresh. [QA-011](../verification/VER-QA-011-RECEIVING.md) records24 new/54 neighbors/736 full regressions and clean analysis/debug packaging. No wallet bytes, server grants or payment confirmation semantics changed; native/Storage/provider/review acceptance stays open.


## App-wide warm presentation — 2026-11-17T08:16:51.570Z

The current user directive/DEC-014 extends welcome/introduction cream, amber and charcoal across this area's screens and overlays, with matching dark mode. [Current design authority](../project/DESIGN.md) and [QA-026](../progress/tasks/QA-026.md) supersede former mint/emerald presentation only. Existing behavior, financial meaning, native QR/image colors and session/durable-save guards remain. Verification must distinguish UI fixtures from actual provider/backend/device acceptance.

2026-11-17T13:24:15.294Z - QA-030: receiving-method editor (including staged registration) and payment entry use full-screen form routes. Method/source/QR choices retain compact sheets at full viewport width; session/draft/QR and acknowledgment guards are unchanged. [Plan](fullscreen-forms-and-edge-sheets.md).
