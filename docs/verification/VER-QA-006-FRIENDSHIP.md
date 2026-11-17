# QA-006 — Friendship consent, resend and acceptance authorization

```json verification-metadata
{
  "id": "VER-QA-006-FRIENDSHIP",
  "task_ids": [
    "QA-006",
    "SEC-002",
    "PRO-003",
    "QR-002",
    "QA-001",
    "REL-001"
  ],
  "timestamp": "2026-11-13T18:49:13.170+08:00",
  "tested_commit": "80d72f3f48a874a81404671c46380d4e608379c0",
  "dirty_tree": true,
  "environment": "Windows; PostgreSQL17.11, PostgREST16.5; disposable local clusters with synthetic Auth/Storage and local self-issued JWT boundary. No deployed roles/accounts or native device.",
  "commands": [
    "node scripts/test-friendship-authorization.cjs",
    "node scripts/test-backend-native.cjs",
    "node .dart_tool/native-db/qa006-local-api.mjs (local-only copy of previously reviewed QA-003 rehearsal; output renamed)",
    "node --check scripts/test-friendship-authorization.cjs",
    "node scripts/check-project-memory.cjs --write; node scripts/check-project-memory.cjs; node scripts/check-project-memory.cjs --base 80d72f3f48a874a81404671c46380d4e608379c0; git diff --check"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "backend-authorization",
      "outcome": "passed"
    },
    {
      "category": "native-postgresql",
      "outcome": "passed"
    },
    {
      "category": "fresh-upgrade",
      "outcome": "passed"
    },
    {
      "category": "schema-snapshot",
      "outcome": "passed"
    },
    {
      "category": "live-backend",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "ios-device",
      "outcome": "unverified"
    },
    {
      "category": "full-platform",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

| Finding | Reproduction on current source | Repair / final result |
|---|---|---|
| Forged accepted friendship bypasses recipient consent | All50 pre-fix migrations on native PG17.11, authenticated A unrelated to B. Before direct INSERT: no B profile/method/avatar visibility. INSERT requester=A,addressee=B,status=accepted succeeds; afterward all three become readable, including actual private method row and avatar object. This demonstrates source policy exposure, not current deployed exposure. | Additive migration removes the legacy requester-only INSERT policy and revokes client INSERT. All four status attempts fail42501. Explicitly regranting INSERT in the fixture still fails RLS; removing the grant alone is not the only defense. Anonymous INSERT/RPC denied. Guarded authenticated request and recipient-only decision remain available. |
| Resend of declined request fails | Positive request → decline → resend reaches unqualified WHERE id in send_friend_request, ambiguous with RETURNS TABLE output; SQLSTATE42702. | Qualify the UPDATE target/key without changing response shape. Reuses the original request ID and becomes pending; replay stays stable. |
| Recipient acceptance fails | Positive accept reaches handle_friendship_notification referencing nonexistent tabs.is_group; SQLSTATE42703 rolls back acceptance. | Use canonical active individual pair. Resolve/create the bilateral tab before status update in the same locked RPC transaction; notification links the actual returned tab. Recipient-only checks and atomic rollback remain. |
| Schema snapshot cannot bootstrap | Whole snapshot parse fails on literal backslash-n separators at two appended migration boundaries. After separator correction it lacks historical notification trigger attachment, caught by the positive notification assertion. | Correct only those separators, retain the exact new migration block and explicitly attach/reaffirm notification trigger/publication in that repair. Standalone snapshot now executes and passes the same authorization/consent journey. |

Final focused [native suite](../../scripts/test-friendship-authorization.cjs) passes three modes: all51 migrations fresh; pre-fix50→51 upgrade with existing friendship row JSON preserved; standalone schema_all. It checks direct statuses/anonymous/RLS-regrant denial, request/replay, self/outsider decision rejection, decline-empty-string compatibility, resend identity, recipient acceptance, expected profile/method/avatar access, unrelated denial, generic accepted-row UPDATE/DELETE denial, exactly two tab members and acceptance notification linkage. Auth/Storage are injected boundary tables/functions; public source grants/policies/triggers/RPCs execute normally as actual native roles. No production account is used.

Final full public-schema/PostgREST rehearsal: fresh51/51,981 statements; reconstructed source-derived baseline upgrade33/33 pending,509 statements;51 history rows; no migration error. Existing HTTP expense/payment/outsider/idempotency/response-loss/QR/proof/correction/account-isolation and M1/group/privacy regressions pass. The copied local harness uses loopback only and retains the [QA-003 environment limitations](VER-QA-003-MOBILE.md). Native financial subset concurrency also passes with eight independent sessions. This is not a full Supabase platform install or actual provider/device acceptance.

### Verification history

Initial new behavioral suite fails after actually forging consent and observing broadened reads. Removing direct access allows positive journeys to reveal the separate42702 resend and42703 notification errors. A generated trigger definition briefly contained a single-dollar delimiter due to JavaScript replacement syntax; corrected the delimiter before acceptance. Extended snapshot execution then locates the two pre-existing malformed separators and missing trigger. Final source passes all three modes, including deliberate table INSERT regrant. No assertion was weakened to hide these failures.

## Evidence

[Additive migration](../../supabase/migrations/20261113000001_friendship_rpc_only.sql), [synchronized/executable snapshot](../../supabase/schema_all.sql), [permanent behavioral test](../../scripts/test-friendship-authorization.cjs), [final source/result/log hashes](QA-006-results.json). Ignored .dart_tool/readiness/qa006-* logs retain initial reproductions and final results. 458 source hashes are recorded. All earlier applied migration hashes match QA-005; only the new migration and snapshot repair change SQL. Pre-existing code/config changes are preserved.

Mobile source/tests/native configuration match [QA-005](VER-QA-005-SOCIAL.md), so its697/697 Flutter, clean analysis and isolated debug APK remain evidence for that unchanged client. No new Flutter run, release APK or device execution is claimed. Prior QA-003/004/005 records remain historical and unmodified.

## Limits and next action

Production remains NO-GO. Repair is local and unapplied remotely. Independent security/migration review and effective deployed policy/grant/migration inventory assessment are required before approved rollout. Existing accepted rows are deliberately retained; status alone does not establish forged consent, and no real-data cleanup is authorized. Real Auth-issued-token direct table/RPC/Storage/Realtime journeys, Android/iOS native lifecycle, provider acceptance and exact clean signed release/upgrade/16KB gates stay open. Broad feature review continues. No deployment, endpoint cutover, cloud spending, remote mutation, messages, staging/commit or publication occurred.
