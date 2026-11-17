# Firebase keyless Android implementation plan

Execution: Codex root implements the already authorized QA-018 setup in this session. Current user instructions to continue execution supersede redundant design/plan approval. No independent review is claimed by this plan.

**Goal:** Deliver permitted Android background reminders through the approved free Firebase project without downloadable service-account keys.

**Architecture:** The existing Azure VM managed identity obtains a short-lived Entra token. A VM-scoped Google workload provider exchanges it and permits impersonation of the FCM-only sender. The worker retains its authenticated gateway, private worker secret, leased queue, data-only payload and account/binding checks. Android uses the existing four public build identifiers; no private sender material enters an APK.

**Tech stack:** Existing Firebase CLI15.36.0, Google IAM/STS/FCM HTTP v1, Azure managed identity, Deno/JavaScript worker and native Android Firebase25.1.3.

**Spec:** [Background reminder contract](../project/BACKGROUND_REMINDERS.md), [QA-018 authorization/task](../progress/tasks/QA-018.md), [product invariants](../project/INSTRUCTIONS.md).

## Constraints and design

- Approved project: project-16899afb-9d76-433c-9a2; billing remains disabled and unattached. No paid resources or analytics enrollment.
- Main package/session/data preserved. Runtime fixtures use com.zalweb.tabby.usbtest only and synthetic accounts; no message to the owner account.
- Google key creation was rejected. Preserve that restriction. Workload federation uses the existing VM identity with exact tenant/object/resource conditions and FCM-only sender role. No general project privilege is added to the VM.
- Original Supabase, disabled signup/M2 and financial rows remain unchanged. Scheduler activation requires its existing release gates; manual bounded synthetic delivery checks do not enable global delivery.
- Source-default client endpoint and unrelated concurrent login/mascot work are preserved.

Alternatives considered: downloadable key fits the original worker but the project rejects it; changing that policy would weaken the account restriction. User OAuth refresh credentials would couple production to a personal login. Use short-lived workload federation instead, consistent with Google multicloud guidance. This choice is the integration owner's implementation decision under the authorized setup.

## Review focus

Expired/malformed identity tokens must stop before STS; arbitrary metadata/STS/impersonation destinations must be rejected before fetch; a denied exchange must never claim jobs; provider acceptance must be distinguished from actual native posting; disposed/account-switched/disabled device scopes must suppress stale messages.

## Task 1 — Provider and worker authentication

Files: `supabase/functions/reminder-push/worker.mjs`, `scripts/test-reminder-push-worker.mjs`, `supabase/functions/reminder-push/index.ts`, reviewed deployment operator under `deploy/azure-full/`.

Interface: `mintFirebaseToken(configuration, {fetcher, now}) -> Promise<string>` continues accepting the existing service-account input and additionally accepts a strictly validated Azure external-account configuration. No public API or queue contract changes.

- [x] Confirm billing off; add Firebase; register main/test Android app IDs and exact signing hashes.
- [x] Reproduce key-creation denial; create FCM-only sender and exact-VM federated trust without keys.
- [ ] Complete live metadata → STS → service-account impersonation → FCM validation probe. Record each boundary as booleans/status only.
- [ ] Add failing tests for the three exchanges, fixed destinations, scope/lifetime, response failures, invalid token shape/expiry, denied authorization without job claims and legacy compatibility.
- [ ] Add the minimal external-account branch with 15-second deadlines, no redirects, validated response tokens/expiry and generic errors.
- [ ] Run worker/packaging tests and Deno source checks. Review exact operator, encrypted backup and rollback before auth/config deployment. Preserve Google Auth and other services.

## Task 2 — Actual isolated Android delivery

Files: dedicated integration fixture and guarded runner under `integration_test/` and `scripts/`, with focused runner safety tests. Public configuration stays ignored locally until exact candidate configuration is prepared.

Interface: isolated fixture reports token/scope through protected private storage; runner forwards it only to the approved sender. Native checks query only that application's NotificationManager. No cross-app notification read or private Home capture.

- [ ] Build/install isolated configured app; verify exact hardware/user/package and permission.
- [ ] Obtain actual FCM registration token without logging it. Send data-only fixture from the Azure federated identity.
- [ ] Verify actual background/closed-process posting separately from provider acceptance, duplicate/stale-binding suppression and opt-out/account cleanup. Record force-stop/reboot/tap separately if not exercised.
- [ ] Retire fixture bindings/private material and remove temporary package. Preserve main owner session.

## Task 3 — Evidence and integration

- [ ] Record deployed provider/config/worker hashes and all failed attempts; update QA-018, background-reminder contract, readiness summaries and index.
- [ ] Run relevant regressions, analysis, project-memory write/plain/base and whitespace/secret checks. Commit only owned changes.
- [ ] Prepare a higher-version normal signed update after runtime validation and concurrent-build coordination; verify certificate/installed bytes and preserve main data. Do not label the full product production ready until every required gate passes.
