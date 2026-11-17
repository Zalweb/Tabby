# security-and-privacy implementation plan

## Purpose and current state

App lock, authorization, session boundaries, privacy/export/deletion controls. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Security agent**.

## Target behavior and contracts

The server enforces membership/ownership/action boundaries independent of UI. Async responses carry initiating account and session generation. Discard responses after either changes. Export only caller-authorized data. Deletion requires reauthentication and preserves shared financial history through documented anonymization/retention. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [SEC-001](../progress/tasks/SEC-001.md) — Cold-launch lock bypass and PIN navigator failure | P1 | Cold launch is protected; PIN dialog opens on resume; cancellation leaves lock active. |
| [SEC-002](../progress/tasks/SEC-002.md) — Pair balance helper lacks caller authorization | P1 | Anon/stranger cannot query any pair balance; legitimate parties and internal RPCs still work. |
| [SEC-003](../progress/tasks/SEC-003.md) — PIN verification has no throttling | P2 | Delay survives restart; correct PIN unlocks; legacy verifier upgrades only after successful verification. |
| [SEC-004](../progress/tasks/SEC-004.md) — Old account loads can commit after session change | P1 | Delay account A response, logout/login B, then release A response; no A data is rendered or cached as B. |
| [SEC-005](../progress/tasks/SEC-005.md) — Privacy, export and deletion journeys are absent | P2 | Export has no unrelated data; deletion request is tracked and does not destroy confirmed shared records. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Implemented checkpoint 2026-10-31T13:57:53.389Z

SEC-001 and SEC-004 now guard cold/resume sensitive mounting and asynchronous account/session results. Settings storage failure keeps the gate closed with retry. The lock owns its navigator for PIN text entry. Same-account relogin is a new generation; token refresh retains the current visible state. See [verification](../verification/VER-SEC-001.md); real Android/SDK acceptance remains open. SEC-003 remains responsible for slow PIN verification, throttling and reset.

## PIN contract checkpoint 2026-10-31T14:04:21.021Z

SEC-003 uses a versioned PBKDF2 verifier with persisted, serialized attempts and escalating delay after five failures. Correct legacy verification upgrades the stored verifier. Local app-PIN replacement/removal/recovery requires fresh platform biometric or device credential authentication; cancellation retains protection. This does not reset a server password. See [verification](../verification/VER-SEC-003.md); Android secure storage/lifecycle/performance acceptance remains open.

## Actor-bound Auth mutations without shared SDK session replacement checkpoint 2026-11-01T13:24:07.002Z

Auth account mutations bind account/session/JWT at initiation and never copy a late user response into the shared SDK session. Verify an acknowledgment belongs to the initiating actor and discard it after account/session changes. Email requests persist an S256 verifier through the same serialized storage adapter/namespace as the SDK; only a genuine subsequent SDK exchange changes its active verified email/session. Preserve latest-link/requesting-device limitations and keep actual provider/device journeys unverified until tested.

See [verification](../verification/VER-SEC-004.md). No deployment; environment-specific limits remain open.

## SEC-005 privacy checkpoint 2026-11-01T18:27:13.348Z

Private profile/owned-contact copy uses export_account_data_v1(), auth.uid-only scoping and an explicit field allowlist. It is not a full account export; exclusions are displayed before requesting it. request_account_deletion_v1() records one review request per caller after recent password/OTP/OAuth/TOTP/SSO AMR authentication, retaining history and forbidding client request mutation. Token refresh iat is insufficient. Flutter discards stale-session acknowledgments and clears displayed personal data on session change. No processing deadline is promised. Full export and reviewed anonymization/retention processing remain unfinished; backend/device deployment checks remain open. See [SEC-005](../progress/tasks/SEC-005.md) and [evidence](../verification/VER-SEC-005.md).

## Privacy export paging and status checkpoint 2026-11-01T18:50:46.205Z

export_ledger_page_v1(section, after, limit) projects authorized tabs/expenses/shares/payments with immutable UUID keyset pagination and 1?100 server row bounds (Flutter requests 50). It has no target-user parameter, omits media/storage URLs, and validates caller membership server-side. Each page is a current read, not a frozen multi-page snapshot. get_account_deletion_request_v1() returns only the caller request or null; status lookup does not require another deletion submission or recent sign-in. See [paging evidence](../verification/VER-SEC-005-PAGES.md). Remaining export/anonymization and environment checks stay open in SEC-005.

## Reviewed anonymization source checkpoint

[SEC-005](../progress/tasks/SEC-005.md) now has a trusted-operator processor with review timestamps, resumable private-media jobs, public-profile/owned-contact/receiving redaction, retired notification/push state and Auth Admin soft deletion. Financial UUIDs, confirmed rows and shared receipt/proof media remain unchanged. Completion is refused until Auth deletion state, session removal and private-media erasure are observed. Auth's profile synchronization cannot restore a redacted profile. Stale issued tokens are denied by the current-database PostgREST request hook, restrictive RLS (including Storage), definer-write and membership guards; new shares for inactive accounts are rejected. A conflicting pre-existing request hook causes migration rollback and requires explicit composition. Private exports now page owner-only receiving details, connections, contacts, notifications and reminders in addition to shared ledger sections. Media bytes, credentials, provider audit and local drafts remain explicitly excluded. See [DEC-010](../project/DECISIONS.md#dec-010--reviewed-privacy-processing-retains-a-redacted-audit-identity) and [operator/runtime limits](../../supabase/functions/account-deletion/README.md). Source fixtures are not live Auth/Storage or full provisioning evidence; deployment/release gates remain open.

## Social session isolation checkpoint 2026-11-13T18:36:38.648+08:00

Friend requests now discard old-account and same-account-relogin results at repository/notifier/UI boundaries; outgoing identity uses the captured session, and late request refresh cannot publish obsolete state. Exact decision acknowledgment and matched friend-code checks prevent misleading success or mismatched identity. SDK loopback dispatch controls did not reproduce token switching; no pinned-token repair is claimed. See [QA-005](../verification/VER-QA-005-SOCIAL.md). Native/real-platform and independent review remain unverified.

## Friendship consent boundary checkpoint 2026-11-13T18:49:13.170+08:00

Friendship creation and acceptance must use authenticated guarded RPCs; direct INSERT cannot manufacture accepted consent or unlock friend-only profile/receiving/avatar access. Additive [QA-006 repair](../verification/VER-QA-006-FRIENDSHIP.md) removes the legacy requester-only policy, qualifies declined resend and repairs acceptance notification/canonical-tab linkage. Fresh51 migrations,50→51 preserved-history upgrade and standalone snapshot pass locally. No deployed remediation or retrospective deletion is claimed; review effective deployed grants/policies and complete real-account/platform acceptance before release.

## Session-bound credential completion checkpoint 2026-11-14T00:45:38.628+08:00

A successful login/signup acknowledgment first waits for the public SDK auth event and requires the exact active Session object before capturing generation. After preference/profile/ledger/profile-check awaits, obsolete or disposed forms cannot change global auth/profile gates or navigate. Optional onboarding write errors are awaited/caught; mounted busy state always clears. [QA-008](../verification/VER-QA-008-AUTH.md) records15 focused/712 full regressions, clean analysis and debug packaging; actual provider/native lifecycle and review remain open. Signup rollout stays unchanged.

## Receiving-view scope checkpoint 2026-11-14T01:22:33.161+08:00

Old-session financial content must disappear from owner/friend/payment sheets and stacked QR dialogs without dismissing newer unrelated routes. Cached callbacks and provider rows bind the initiating generation, including relogin with unchanged profile identity. Clipboard dispatch acknowledges success/error only in the active scope. See [QA-011](../verification/VER-QA-011-RECEIVING.md); this is local UI/provider evidence, not deployed policy or native wallet acceptance.


## App-wide warm presentation — 2026-11-17T08:16:51.570Z

The current user directive/DEC-014 extends welcome/introduction cream, amber and charcoal across this area's screens and overlays, with matching dark mode. [Current design authority](../project/DESIGN.md) and [QA-026](../progress/tasks/QA-026.md) supersede former mint/emerald presentation only. Existing behavior, financial meaning, native QR/image colors and session/durable-save guards remain. Verification must distinguish UI fixtures from actual provider/backend/device acceptance.
