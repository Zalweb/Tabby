# M2 disposable Supabase/Auth staging attempt

```json verification-metadata
{
  "id": "VER-M2-SUPABASE-AUTH-STAGING",
  "task_ids": ["CAP-002", "CAP-003", "CAP-004", "CAP-005", "QA-001"],
  "tested_commit": "7667f3e1141bfee314fb7e51215d891ceb36ce84",
  "dirty_tree": true,
  "timestamp": "2026-11-04T03:10:18+08:00",
  "environment": "Windows; Flutter 3.47.8 / Dart 3.13.7; native PostgreSQL 17.11; Supabase CLI 3.0.0 invoked with npx",
  "checks": [
    {"category": "flutter-analysis", "outcome": "passed"},
    {"category": "flutter-regression", "outcome": "passed"},
    {"category": "m2-native-sql-contracts", "outcome": "passed"},
    {"category": "m2-schema-snapshot", "outcome": "passed"},
    {"category": "disposable-supabase-provisioning", "outcome": "failed"},
    {"category": "fresh-supabase-install", "outcome": "unverified"},
    {"category": "supabase-upgrade", "outcome": "unverified"},
    {"category": "auth-issued-jwt-postgrest", "outcome": "unverified"},
    {"category": "m2-live-authenticated-journeys", "outcome": "unverified"},
    {"category": "android-device", "outcome": "unverified"}
  ],
  "commands": [
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub",
    "node scripts/test-backend-native.cjs",
    "node --test scripts/test-m2-schema-snapshot.cjs",
    "npx.cmd --yes supabase --version",
    "npx.cmd --yes supabase start",
    "adb devices -l"
  ]
}
```

## Expected and actual results

Expected: start disposable Supabase environments for a full fresh install and the reconstructed upgrade, with Auth issuing real JWTs. Use those tokens against local PostgREST/RPC to verify each feature's authenticated role, grants, policies, acceptance and denial paths. Actual: the Supabase CLI was available (`3.0.0`), but `supabase start` stopped before provisioning because Docker and Podman are absent. No disposable hosted project was available: a read-only Management API project listing returned only production `Tabby` (`ziaqrkagsvozhotremsx`), and the organization-detail GET returned HTTP 403. No project creation, production mutation, config change, migration or deployment was attempted.

Flutter analysis passed: `No issues found!` in 87.5 seconds. The complete Flutter suite passed **650/650**. `node scripts/test-backend-native.cjs` passed its PostgreSQL 17.11 source-subset assertions, including each M2 feature contract and concurrency scenario. `node --test scripts/test-m2-schema-snapshot.cjs` passed **1/1**. Those native checks use disposable SQL fixtures with `SET ROLE authenticated` and injected JWT-subject settings; they are source/regression evidence, not Auth-issued JWTs, a Supabase Auth service, or PostgREST acceptance.

## Per-feature results

| Task | Local native SQL evidence actually run | Disposable Supabase Auth/PostgREST result |
|---|---|---|
| [CAP-002](../progress/tasks/CAP-002.md) | Custom split: disabled-rollout denial, independent integer tax/service charges, odd-cent and zero allocations, persisted breakdown, replay/conflict, role isolation and eight-session concurrency passed. | Not run; no Auth-issued JWT/API environment. |
| [CAP-003](../progress/tasks/CAP-003.md) | Recurrence: disabled-rollout denial, calendar/month-end/DST, owner/replay/conflict, pause/resume/end, immutable history, scheduler replay and eight-session occurrence race passed. | Not run; no Auth-issued JWT/API environment or deployed scheduler. |
| [CAP-004](../progress/tasks/CAP-004.md) | Claiming: explicit target consent, decline with no identity/financial change, stale/foreign denial, retained contact history, both balance directions, replay and eight-session accept race passed. | Not run; no Auth-issued JWT/API environment. |
| [CAP-005](../progress/tasks/CAP-005.md) | Review: explicit acknowledgment/creator denial, outsider isolation, rejected proposal with no financial effect, dispute/resolution votes, unanimous resolution, replay/conflict, immutable source rows and eight-session decision races passed. | Not run; no Auth-issued JWT/API environment. |

All four application rollout constants remain false. The SQL migration source seeds all four database feature flags false; the local native harness temporarily enables flags only inside its disposable cluster for behavior checks, then tears that cluster down. No M2 flag was changed in production or another persistent environment.

## Reconciliation with prior QA evidence

[VER-QA-001-LOCAL-UPGRADE-AUTH](VER-QA-001-LOCAL-UPGRADE-AUTH.md) records the prior native PostgreSQL 17.11 fresh-install and reconstructed-upgrade result, the M1 local PostgREST journeys, and the `20261031000001` authorization probe. That run used a local PostgREST/JWT harness and did not include a Supabase Auth service. This run adds current full Flutter analysis/tests and all four M2 native SQL contracts, but it does not supersede or close the prior evidence's physical-catalog limitation, production authorization gate, or QA-001/REL-001 acceptance gates.

## Evidence

- Flutter 3.47.8 / Dart 3.13.7: analysis passed and full suite **650/650** passed.
- Native PostgreSQL 17.11 output included `M2_CUSTOM_SPLIT_OK`, `RECURRENCE_CONTRACT_OK`, `CONTACT_CLAIM_CONTRACT_OK`, `EXPENSE_REVIEW_CONTRACT_OK`, all corresponding concurrency markers, and `NATIVE_CONCURRENCY_OK`.
- M2 consolidated migration snapshot parity: **1 test passed, 0 failed**.
- Supabase CLI local startup actual error: `DockerLifecycleInspectError: failed to inspect container health: docker: command not found (podman also not found)`.
- `adb devices -l`: no attached device.

## Limits and next action

No M2 fresh/upgrade migration was run in a Supabase environment; no Auth-issued JWT or M2 PostgREST journey was exercised. The M2 native checks are limited to SQL fixtures and do not satisfy the requested authenticated Supabase gate. QA-001 and REL-001 remain open; all 11 Android device gates remain open. M1 live-backend and production-authorization results remain unchanged and unverified for release. Keep application/database M2 rollout disabled and production untouched. Next: provide a disposable Supabase runtime with Docker/Podman (or a separately authorized disposable hosted project) and run the fresh/upgrade Auth/PostgREST matrix there; run device acceptance when hardware is attached.
