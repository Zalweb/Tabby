# groups-and-expenses implementation plan

## Purpose and current state

Explicit party allocations, atomic group creation and pair-specific settlement. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Ledger/UI agent**.

## Target behavior and contracts

PartyRef identifies user or contact, never a group. Expense commands carry all allocations and actual payer. Shares are nonnegative integer centavos summing exactly to total; the payer is one of the participants. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [GRP-001](../progress/tasks/GRP-001.md) — Group payments change uninvolved balances | P1 | Bob-to-Carol payment leaves Alice unchanged on server, cache, UI and after refresh. |
| [GRP-002](../progress/tasks/GRP-002.md) — Group shares and payer selection are incomplete | P1 | Three/five-member odd-cent bills calculate correctly for each possible payer and perspective. |
| [GRP-003](../progress/tasks/GRP-003.md) — Group settlement treats a group as a person | P1 | Group debtor opens the actual creditor QR and settles only that pair obligation. |
| [GRP-004](../progress/tasks/GRP-004.md) — Group creation is partially committed | P2 | Inject failure at each step; no partial group remains and a retry creates one complete group. |
| [GRP-005](../progress/tasks/GRP-005.md) — Malformed currency is accepted or throws without feedback | P2 | Reject abc.50, 1.234, exponent and overflow input; accept valid formatted PHP exactly. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Payment isolation checkpoint 2026-10-31T14:07:35.191Z

GRP-001 now applies payments only to actual payer/recipient and preserves those identities through parse/cache/refresh. An ambiguous legacy recipient needs authoritative refresh; no nonpayer is inferred to be a recipient. See [verification](../verification/VER-GRP-001.md). Real local financial SQL and eight-session replay tests pass; full Supabase/device acceptance remains open.

## Allocation checkpoint 2026-10-31T14:14:34.193Z

Group expense commands preserve each member share and actual payer through form/queue/RPC/cache. Equal remainder allocation uses immutable ID order; it is independent of payer and viewer. The existing Full share choice is labeled Others split for groups: payer gets zero and the total is equally split among all other members. Arbitrary custom splits remain hidden M2. Missing group roster or legacy queued aggregate needs refresh/review. See [verification](../verification/VER-GRP-002.md).

## Actual-member group settlement checkpoint 2026-10-31T14:18:37.041Z

Group settlement exposes direct immutable member-pair obligations without redirecting debts through uninvolved members. A zero aggregate balance can retain obligations. Payment info names the creditor, payment validation uses the selected pair, and outgoing submission leaves the balance unchanged until confirmation. Incoming manual group recording is explicitly cash received.

See [verification](../verification/VER-GRP-003.md). No deployment; environment-specific limits remain open.

## Atomic retry-safe group creation checkpoint 2026-10-31T14:22:09.925Z

create_group_v1 takes actor-scoped operation UUID plus exact name/member_user_ids command. All five creation stages commit or roll back together. Same ID/payload returns original group/tab; changed payload conflicts. Only distinct accepted registered friends can join. Live Flutter publishes group success after RPC success; form retains operation identity for retry.

See [verification](../verification/VER-GRP-004.md). No deployment; environment-specific limits remain open.

## Strict PHP input and amount limits checkpoint 2026-10-31T14:25:55.961Z

New expense/payment/share amounts use integer centavos and are bounded by 99999999999 centavos. Decimal input permits at most two fractional digits and correctly grouped thousands; exponent notation and partial parsing are rejected. Existing oversized history is retained for explicit review through NOT VALID database constraints.

See [verification](../verification/VER-GRP-005.md). No deployment; environment-specific limits remain open.

## Normalized API validation response checkpoint 2026-11-04T07:10:00+08:00

Client-facing JSON financial RPCs normalize PostgreSQL text/range conversion failures to HTTP 400 with PostgREST code `PT400` and message `Invalid financial input. Enter amounts as whole centavos and check the submitted values.` The response has no SQLSTATE/type/parser detail or hint. This preserves integer-centavo storage and commits no row on invalid input. Keep M2 flags disabled; the M2 RPC wrappers have the same boundary but were not enabled or exercised. Local M1 API acceptance is recorded in [VER-GRP-005-API-ERROR-BOUNDARY](../verification/VER-GRP-005-API-ERROR-BOUNDARY.md); live deployment/acceptance remains open.


## App-wide warm presentation — 2026-11-17T08:16:51.570Z

The current user directive/DEC-014 extends welcome/introduction cream, amber and charcoal across this area's screens and overlays, with matching dark mode. [Current design authority](../project/DESIGN.md) and [QA-026](../progress/tasks/QA-026.md) supersede former mint/emerald presentation only. Existing behavior, financial meaning, native QR/image colors and session/durable-save guards remain. Verification must distinguish UI fixtures from actual provider/backend/device acceptance.

2026-11-17T10:06:37.311Z ? QA-029 UI audit: shared sheet feedback prevents covered Add/group errors; the Add wizard scrolls its whole content and wraps progress/input controls for keyboard/large text. Financial and durable-draft behavior is unchanged. [UI audit plan](ui-feedback-audit.md).

2026-11-17T13:24:15.294Z - QA-030: Add Tab/group creation/payment entry now use full-screen form routes and pinned Back with scrolling fields. Quick choices remain full-width compact sheets; preserve durable drafts, step-back and financial semantics. [Plan](fullscreen-forms-and-edge-sheets.md).

2026-11-17T14:30:25.234Z - QA-031 Add success now shows finite art-only celebration; payment entry details show waiting for submitted/pending and celebration only for settled existing status. No financial data mutation or confirmation inference. QA-032 expense integration remains separately owned/unshipped in mascot-only candidate19. [Mascot plan](situation-mascot-animation.md).


## Existing-tab and plain custom entry contract — 2026-11-17T18:55:00.494Z

Registered one-person selection now reads the canonical pair by immutable IDs, confirms Add/View/Cancel, and sends Add to the exact existing tab ID. Group creation is explicit. Custom amounts include every roster party with a nonnegative integer centavo share, including a zero-share payer; shares sum exactly to the total. 45000→0/15000/30000 uses the existing M1 explicit-participant writer. Duplicate hints compare full expense context and permit deliberate new same-amount operations. Manual contacts retain identity and are never merged by name. See [QA-032](../progress/tasks/QA-032.md) for evidence and remaining limits.
