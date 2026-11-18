# Project instructions

## Product invariants

- Audience: Philippine friends, classmates, roommates and couples. Tagline: Keep tabs. Settle up.
- Friendship first: calm conversational English, no emoji UI copy, no debt-collector language or routine red warning banners. Aim for under-five-second repeat expense entry.
- One running bilateral relationship per immutable pair. Group obligations retain explicit parties; groups never act as people.
- Amounts and allocations are integer centavos (100 centavos = PHP 1). No floating-point ledger arithmetic.
- Confirmed financial history is append-only. Corrections/cancellations retain originals and reasons with counterpart visibility. Unfriending never deletes debts.
- No money movement: saved wallet-issued receiving QR → external payment → explicit submission → recipient verification/confirmation → balance change. Scanning/uploading proof never confirms money received.
- Saved method visibility: owner, accepted friends on profile, and actual debtors in payment flow (including groups). Never public by default. Server authorization is mandatory.
- Registered accepted friends only in groups; unregistered contacts are bilateral tab-only parties. Contact conversion requires explicit consent.

## Work protocol

Read root instructions, index, decisions, status, relevant plan and dependency records at session start. Register identity/platform, branch/base commit, claimed scope and file reservations in the task before edits. Review changed claims again before touching shared files. An unassigned task with completed dependencies may be claimed. A stale claim (no update for 24 hours) requires coordination or a documented takeover reason; it is not automatically released.

Integration owner serializes edits to central state/models, routing, dependencies, schema_all.sql and CI. Use separate worktrees and small reviewable commits. Resolve conflicting assumptions in DECISIONS.md and affected plans before dependent changes. Record blockers without claiming completion.

Every code/config/docs change ships with an updated task record: what changed, what remains incomplete/unverified, relevant tests and actual results, deployment status, next action. Run the documentation checker with the task base commit. Do not rewrite history to hide failures.

## Completion

Implemented means code exists; verified means required acceptance passed in recorded environments; complete also requires integration/review and current documentation. If device/backend tools are unavailable, leave those checks unverified and name the needed next step. A passing unit/mock suite cannot close a live authorization or Android-device finding.

No secrets or private user data in Git or evidence. Use sanitized fixtures. Deployment evidence must identify environment and applied migration versions; publishing requires exact candidate artifact evidence and existing authorization.

## Live website deployment preference

2026-11-18T19:58:27+08:00 — Explicit owner instruction: always deploy completed website and landing-page changes to the live production site. After relevant tests and browser verification pass, publish through the existing Vercel production path as part of delivery without asking for the same approval again; a local build, preview URL or unmerged branch is not delivery. Record the production URL, deployment commit and any unverified checks. Backend deployment, app release and signing gates are unchanged.
