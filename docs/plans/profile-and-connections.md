# profile-and-connections implementation plan

## Purpose and current state

Persisted profile updates, real avatars, accurate friend/archive/settings behavior. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Profile agent**.

## Target behavior and contracts

Await writes and retain draft on failure. Auth email changes use verification. Private nicknames never mutate another account profile. Unfriend preserves financial records. Archive is reversible and never described as deletion. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [PRO-001](../progress/tasks/PRO-001.md) — Profile writes can report false success | P2 | Server rejection preserves form; email changes only after verification; payment methods remain consistent. |
| [PRO-002](../progress/tasks/PRO-002.md) — Avatar camera/gallery choices are placeholders | P2 | Chosen gallery/camera image persists across restart; cancel does not report success. |
| [PRO-003](../progress/tasks/PRO-003.md) — Friend and group actions overstate persistence/deletion | P2 | Failure remains visible; archive restores; unfriending preserves tabs and financial records. |
| [PRO-004](../progress/tasks/PRO-004.md) — Preferences are partially implemented | P3 | No nonfunctional preference remains; core screens pass light/dark/reduced-motion widget checks. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Acknowledged profile writes and Auth-owned email checkpoint 2026-11-01T06:03:43.810Z

Core profile saves use owner-scoped update_profile_v1 and acknowledge the stored row. Public profile email follows Auth; proposed email is never a profile write. Email verification is a separate action governed by server Auth confirmation settings (enabled in local config, hosted configuration unverified). Auth refresh/confirmed email changes preserve saved name/phone/avatar. Receiving destinations are edited only through saved methods; no partial fallback may claim success for omitted fields.

See [verification](../verification/VER-PRO-001.md). No deployment; environment-specific limits remain open.

## Real profile photo drafts and private avatar objects checkpoint 2026-11-01T12:38:25.993Z

A selected profile photo is an account-scoped retained draft, not an upload acknowledgment. Use real camera/gallery, bounded canonical PNG preview and immutable owner object path. Upload first, then acknowledge the profile row before closing; preserve the same bytes/path on retry/restart. Photos are private and current-reference visibility is limited to the owner, accepted friends and active tab peers. Removal clears the current profile reference; orphan/historical object retention requires explicit privacy cleanup.

See [verification](../verification/VER-PRO-002.md). No deployment; environment-specific limits remain open.

## Private connections and acknowledged social changes checkpoint 2026-11-01T13:05:38.561Z

Nicknames are private caller-owned Connections labels; profile identity and receiving details remain owner controlled. Archive/restore changes only the caller's Connections view, preserving active shared ledger access, balances and reminders even for unpaid groups. Unfriend changes only the social relationship after acknowledgment. Commands bind initiating owner, stable operation and expected private-preference revision; replay returns the original result and stale competing intents fail for review. Profile updates now use actor-bound v2. Shared Auth SDK mutations remain a separately tracked follow-up.

See [verification](../verification/VER-PRO-003.md). No deployment; environment-specific limits remain open.

## Acknowledged appearance, fixed PHP English and system reduced motion checkpoint 2026-11-01T14:17:14.656Z

PHP and English are the only exposed/supported M1 preferences. Appearance changes acknowledge encrypted account storage before updating displayed values; failed writes preserve prior settings. Semantic themes retain emerald branding and never recolor QR/receipt pixels. Reduced motion is user-disabled OR system-disabled and applies to routes, dialogs, sheets, explicit animations and mascot behavior.

See [verification](../verification/VER-PRO-004.md). No deployment; environment-specific limits remain open.

## Account-bound friend requests checkpoint 2026-11-13T18:36:38.648+08:00

Friend lookup/send/list/respond acknowledgments bind the initiating account/session generation; decision success validates exact request/status and accepted UUID or declined empty string. ConnectByIdSheet dismisses on account/relogin, discards matches when the ID changes, and freezes identity while sending. Request decisions permit one pending action per request. No SQL/wire/consent change. See [QA-005](../verification/VER-QA-005-SOCIAL.md); real Auth/Realtime/device acceptance remains open.

## Friendship consent boundary checkpoint 2026-11-13T18:49:13.170+08:00

Friendship creation and acceptance must use authenticated guarded RPCs; direct INSERT cannot manufacture accepted consent or unlock friend-only profile/receiving/avatar access. Additive [QA-006 repair](../verification/VER-QA-006-FRIENDSHIP.md) removes the legacy requester-only policy, qualifies declined resend and repairs acceptance notification/canonical-tab linkage. Fresh51 migrations,50→51 preserved-history upgrade and standalone snapshot pass locally. No deployed remediation or retrospective deletion is claimed; review effective deployed grants/policies and complete real-account/platform acceptance before release.

## Pair-concurrent request creation checkpoint 2026-11-13T18:57:37.739+08:00

send_friend_request serializes the canonical immutable pair before reading/creating a request. Same-direction retries reuse one pending ID; opposite sends preserve the incoming request and require explicit acceptance. No historical duplicate cleanup or implicit consent. [QA-007](../verification/VER-QA-007-SOCIAL-CONCURRENCY.md) records actual native-session races over fresh/upgrade/snapshot fixtures; deployed/native/Realtime acceptance remains open.


## App-wide warm presentation — 2026-11-17T08:16:51.570Z

The current user directive/DEC-014 extends welcome/introduction cream, amber and charcoal across this area's screens and overlays, with matching dark mode. [Current design authority](../project/DESIGN.md) and [QA-026](../progress/tasks/QA-026.md) supersede former mint/emerald presentation only. Existing behavior, financial meaning, native QR/image colors and session/durable-save guards remain. Verification must distinguish UI fixtures from actual provider/backend/device acceptance.


2026-11-17T09:27:12.728Z — [QA-028](../progress/tasks/QA-028.md) rounds/insets appearance choices, adapts identity at200% text and removes non-actionable PHP/English preference rows/provider-advertising duplication. Real security/receiving/friend/group/privacy/appearance/support actions and persistence guards remain.

2026-11-17T10:06:37.311Z ? QA-029: settings/profile/connection sheets use route-scoped visible feedback; closed-form success returns to the active parent/page. Existing inline save errors stay intact. No Profile Add FAB. [UI audit plan](ui-feedback-audit.md).

2026-11-17T13:24:15.294Z - QA-030: Edit Profile/group creation use full-screen routes; Appearance/avatar/security/notification/connection quick choices remain content-height sheets with edge-to-edge width. Actual surface geometry/large-text/back are tested. [Plan](fullscreen-forms-and-edge-sheets.md).
