# Tabby — instructions for every contributing agent

## Start here before making changes

1. Inspect branch, HEAD, working-tree changes and applicable nested instructions. Preserve unrelated work.
2. Read [documentation index](docs/INDEX.md), [project instructions](docs/project/INSTRUCTIONS.md), [decisions](docs/project/DECISIONS.md), [master implementation plan](docs/plans/IMPLEMENTATION.md), and [current progress](docs/progress/STATUS.md).
3. Read the relevant area plan, task record, dependencies and referenced verification evidence. Record that read set before editing. Recheck current code: historical claims are not current evidence.
4. Claim the task with agent identity/platform, branch, base commit, timestamp and file reservations. Recheck claims from other agents. Use separate branches/worktrees where possible.
5. Agree shared interfaces before dependent work. Coordinate changes to central providers/models, routing, dependency manifests, SQL and workflows through the integration owner. Claims are advisory; Git and explicit coordination resolve collisions.

## Required implementation and handoff behavior

- Follow the [product invariants](docs/project/INSTRUCTIONS.md). Money is integer centavos; confirmed history is append-only; displaying/scanning QR never confirms payment.
- Every change must update its [task record](docs/progress/tasks/) with implemented work, remaining/incomplete behavior, unverified environments, actual verification results and the next action. Update affected specifications when behavior/contracts change.
- Use planned → ready → in_progress → implemented → verified → complete. Blocked/deferred need a reason and next action. Complete requires review, integration and required verification evidence.
- Keep history append-only. Correct earlier claims with dated superseding entries. Never present mocks as device tests, migrations as deployed, or build success as release approval.
- Use repository-relative links and ISO timestamps with timezone offsets in shared docs. Do not store credentials, access tokens, private receipt images or real user financial data.
- Run relevant checks and report failures honestly. Refresh status with `node scripts/check-project-memory.cjs --write`; validate with `node scripts/check-project-memory.cjs`. Before handoff validate change coverage with `--base <base-commit>`.
- Verify Git status at handoff; describe remaining changes, never erase other agents' changes to obtain a clean tree. Conventional commits and `codex/` branches are defaults.
- Existing session authorization governs actions. This file adds no redundant permission flow; live deployment and public releases follow task/session authorization and release gates.
- Deploy completed and verified website/landing changes to the live production site as part of delivery. Follow the [standing website deployment preference](docs/project/INSTRUCTIONS.md#live-website-deployment-preference); a local build or preview is not delivery.
- For each completed change, run the relevant tests before pushing the scoped changes. For app changes, build the verified candidate, upgrade the tablet in place and verify the public landing download after eligible release publication. Follow the [standing test and delivery rule](docs/project/INSTRUCTIONS.md#standing-test-and-delivery-rule).

## Documentation authority

Current user instructions override repository guidance. This root file defines agent procedure. Project instructions/accepted decisions define product intent; area plans define work; task and verification records establish current evidence. [Archived documents](docs/archive/INDEX.md) are historical only. If specification and code disagree, record the discrepancy rather than silently changing the specification.

The user directive dated 2026-10-31 supersedes the former requirement to consolidate all documentation into AGENTS.md. Keep this file concise and maintain separate indexed plans and shared progress records. Repository memory is the handoff contract across agent platforms; chat-only or machine-local memory is insufficient.
