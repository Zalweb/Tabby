# M1 acceptance and review reconciliation

```json verification-metadata
{
  "id": "VER-M1-ACCEPTANCE-REVIEW",
  "task_ids": [
    "AND-001",
    "AND-002",
    "AND-003",
    "AND-004",
    "AND-005",
    "AUTH-001",
    "AUTH-002",
    "AUTH-003",
    "AUTH-004",
    "AUTH-005",
    "CAP-001",
    "CAP-006",
    "GRP-001",
    "GRP-002",
    "GRP-003",
    "GRP-004",
    "GRP-005",
    "HOME-001",
    "HOME-002",
    "HOME-003",
    "HOME-004",
    "INT-001",
    "LED-001",
    "LED-002",
    "LED-003",
    "LED-004",
    "LED-005",
    "LED-006",
    "PAY-001",
    "PAY-002",
    "PAY-003",
    "PAY-004",
    "PRO-001",
    "PRO-002",
    "PRO-003",
    "PRO-004",
    "QR-001",
    "QR-002",
    "QR-003",
    "QR-004",
    "QR-005",
    "QR-006",
    "SEC-001",
    "SEC-002",
    "SEC-003",
    "SEC-004",
    "SEC-005",
    "QA-001"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "local-acceptance-review",
      "outcome": "passed"
    },
    {
      "category": "backend-contract",
      "outcome": "passed"
    },
    {
      "category": "native-concurrency",
      "outcome": "passed"
    },
    {
      "category": "documentation",
      "outcome": "passed"
    },
    {
      "category": "integration",
      "outcome": "unverified"
    },
    {
      "category": "backend-integration",
      "outcome": "unverified"
    },
    {
      "category": "live-backend",
      "outcome": "unverified"
    },
    {
      "category": "android-device",
      "outcome": "unverified"
    },
    {
      "category": "release-artifact",
      "outcome": "unverified"
    }
  ],
  "timestamp": "2026-11-01T23:41:43.428Z",
  "tested_commit": "14d1cd6d262e9ce39992e8d3258a358ed318d366",
  "dirty_tree": true,
  "environment": "Windows; Flutter3.47.8; real local PostgreSQL17.11 source migration subset with injected Auth claims; no connected adb device, Supabase CLI/connector or authenticated live project.",
  "commands": [
    "flutter analyze --no-pub lib test scripts",
    "flutter test --no-pub",
    "node scripts/test-backend-native.cjs",
    "node --test scripts/check-project-memory.test.cjs",
    "adb devices -l",
    "node scripts/check-project-memory.cjs --write",
    "node scripts/check-project-memory.cjs --base 14d1cd6d262e9ce39992e8d3258a358ed318d366"
  ]
}
```

## Expected and actual results

M1 source coverage47/47 and genuine completion1/47 are both correct. Flutter628/628 and clean analysis of all Dart roots pass. Real local PostgreSQL source behavior and eight-session financial/social/correction races pass. Project-memory regressions6/6 pass, including source coverage never incrementing verified/complete counts. The first broad analyzer run stalled and was stopped; the successful scoped command covers lib, test and scripts. No external gate was promoted.

## Evidence

Current task acceptance and linked evidence were reconciled; local review is explicitly narrower than independent/integrated acceptance. Known existing-source contracts remain in force. Logs are ignored .dart_tool/m1-review-final-{analysis,tests}.log and m1-review-backend.log.

| Task | Acceptance scenario | Remaining unverified gate |
|---|---|---|
| [AND-001](../progress/tasks/AND-001.md) | Scheduled reminder fires with permission allowed/denied fallback and survives reboot appropriately. | android-device, integration-review |
| [AND-002](../progress/tasks/AND-002.md) | Restore to another device does not crash; session/cache recover safely without exposing data. | android-device, integration-review |
| [AND-003](../progress/tasks/AND-003.md) | Kill/recreate during picker, recover image/draft; back returns a step or asks before discarding edits. | android-device, integration-review |
| [AND-004](../progress/tasks/AND-004.md) | Profile 100 tabs/10000 entries on low-memory Android; page rendering remains responsive and queue survives interrupted migration. | android-device, integration-review |
| [AND-005](../progress/tasks/AND-005.md) | Main/tag/manual publication cannot upload debug APK; installed prior release upgrades preserving data and OAuth works. | android-device, integration-review, release-artifact, upgrade |
| [AUTH-001](../progress/tasks/AUTH-001.md) | Storage exception, notification exception and offline profile fetch each show recoverable UI. | integration, integration-review, live-backend |
| [AUTH-002](../progress/tasks/AUTH-002.md) | Cold/warm valid recovery works; expired/used tokens fail safely; resend obeys service limits. | integration, integration-review, live-backend |
| [AUTH-003](../progress/tasks/AUTH-003.md) | One upload fails among multiple methods; saved items do not duplicate and failure remains actionable. | integration, integration-review, live-backend |
| [AUTH-004](../progress/tasks/AUTH-004.md) | 09/+639/639 equivalents normalize identically; invalid prefixes fail; profile phone does not automatically enable GCash. | integration, integration-review, live-backend |
| [AUTH-005](../progress/tasks/AUTH-005.md) | Small/landscape/200 percent text screens remain usable; back follows steps then exits normally. | integration, integration-review, live-backend |
| [CAP-001](../progress/tasks/CAP-001.md) | Every missing capability maps to a task and hidden/available behavior matches its verified status. | integration, integration-review, live-backend |
| [CAP-006](../progress/tasks/CAP-006.md) | Wrong expense can be corrected without deletion; each party sees the revision and balances replay exactly. | integration, integration-review, live-backend |
| [GRP-001](../progress/tasks/GRP-001.md) | Bob-to-Carol payment leaves Alice unchanged on server, cache, UI and after refresh. | backend-integration, integration-review, live-backend |
| [GRP-002](../progress/tasks/GRP-002.md) | Three/five-member odd-cent bills calculate correctly for each possible payer and perspective. | backend-integration, integration-review, live-backend |
| [GRP-003](../progress/tasks/GRP-003.md) | Group debtor opens the actual creditor QR and settles only that pair obligation. | backend-integration, integration-review, live-backend |
| [GRP-004](../progress/tasks/GRP-004.md) | Inject failure at each step; no partial group remains and a retry creates one complete group. | backend-integration, integration-review, live-backend |
| [GRP-005](../progress/tasks/GRP-005.md) | Reject abc.50, 1.234, exponent and overflow input; accept valid formatted PHP exactly. | backend-integration, integration-review, live-backend |
| [HOME-001](../progress/tasks/HOME-001.md) | Boundary dates filter correctly and KPIs match outstanding obligations rather than spending. | android-device, integration-review |
| [HOME-002](../progress/tasks/HOME-002.md) | Settle dated debt, refresh/restart/reconnect: no reminder or overdue alert returns. | android-device, integration-review |
| [HOME-003](../progress/tasks/HOME-003.md) | Fresh permission allow/deny, disable preferences and logout each produce the expected alert behavior. | android-device, integration-review |
| [HOME-004](../progress/tasks/HOME-004.md) | Offline/rejected sends do not claim sent; closed app receives accepted reminders and tap opens authorized target. | android-device, integration-review |
| [INT-001](../progress/tasks/INT-001.md) | Frozen shared contracts and dependency fixtures | contract complete |
| [LED-001](../progress/tasks/LED-001.md) | Two registered Alex accounts and two same-name groups remain separate after refresh and restart. | backend-integration, integration-review, live-backend |
| [LED-002](../progress/tasks/LED-002.md) | Lunch and Coffee at the same price ten minutes apart both survive local/server refresh. | backend-integration, integration-review, live-backend |
| [LED-003](../progress/tasks/LED-003.md) | Drop the response after commit and retry concurrently; exactly one expense/payment exists. | backend-integration, integration-review, live-backend |
| [LED-004](../progress/tasks/LED-004.md) | Permanent failures become needsAttention; retry count does not grow while idle; transient retries are delayed. | backend-integration, integration-review, live-backend |
| [LED-005](../progress/tasks/LED-005.md) | A contact can pay or owe; expenses and partial cash settlements persist through refresh/restart. | backend-integration, integration-review, live-backend |
| [LED-006](../progress/tasks/LED-006.md) | Server errors with connectivity available show failure, retain cache and never report synchronized. | backend-integration, integration-review, live-backend |
| [PAY-001](../progress/tasks/PAY-001.md) | Recipient confirms pending submission once; no additional payment row appears. | backend-integration, integration, integration-review, live-backend |
| [PAY-002](../progress/tasks/PAY-002.md) | Payer submits proof offline/online and recipient sees it on the same payment. | backend-integration, integration, integration-review, live-backend |
| [PAY-003](../progress/tasks/PAY-003.md) | Unverified files never receive a verified label; offline attachment survives process death and sync. | backend-integration, integration, integration-review, live-backend |
| [PAY-004](../progress/tasks/PAY-004.md) | Concurrent confirmations whose sum exceeds debt cannot both succeed; exact debt never becomes overpaid. | backend-integration, integration, integration-review, live-backend |
| [PRO-001](../progress/tasks/PRO-001.md) | Server rejection preserves form; email changes only after verification; payment methods remain consistent. | integration, integration-review, live-backend |
| [PRO-002](../progress/tasks/PRO-002.md) | Chosen gallery/camera image persists across restart; cancel does not report success. | integration, integration-review, live-backend |
| [PRO-003](../progress/tasks/PRO-003.md) | Failure remains visible; archive restores; unfriending preserves tabs and financial records. | integration, integration-review, live-backend |
| [PRO-004](../progress/tasks/PRO-004.md) | No nonfunctional preference remains; core screens pass light/dark/reduced-motion widget checks. | integration, integration-review, live-backend |
| [QR-001](../progress/tasks/QR-001.md) | Setup offers upload and rejects non-QR images; no generic account-number QR appears. | backend-authorization, integration, integration-review, live-backend |
| [QR-002](../progress/tasks/QR-002.md) | Two authenticated accounts load a permitted image; stranger/anon and guessed paths fail. | backend-authorization, integration, integration-review, live-backend |
| [QR-003](../progress/tasks/QR-003.md) | Upload failure preserves old method; successful replacement appears on another device. | backend-authorization, integration, integration-review, live-backend |
| [QR-004](../progress/tasks/QR-004.md) | Expire URL, reopen flow, update/remove method from another session; correct state appears. | backend-authorization, integration, integration-review, live-backend |
| [QR-005](../progress/tasks/QR-005.md) | Add nondefault preserves preference; remove default promotes exactly one remaining method. | backend-authorization, integration, integration-review, live-backend |
| [QR-006](../progress/tasks/QR-006.md) | Wallet import works on one phone; unreadable images fail; friend/debtor access matches the agreed matrix. | backend-authorization, integration, integration-review, live-backend |
| [SEC-001](../progress/tasks/SEC-001.md) | Cold launch is protected; PIN dialog opens on resume; cancellation leaves lock active. | android-device, integration-review |
| [SEC-002](../progress/tasks/SEC-002.md) | Anon/stranger cannot query any pair balance; legitimate parties and internal RPCs still work. | backend-authorization, integration-review, live-backend |
| [SEC-003](../progress/tasks/SEC-003.md) | Delay survives restart; correct PIN unlocks; legacy verifier upgrades only after successful verification. | android-device, integration-review |
| [SEC-004](../progress/tasks/SEC-004.md) | Delay account A response, logout/login B, then release A response; no A data is rendered or cached as B. | integration, integration-review, live-backend |
| [SEC-005](../progress/tasks/SEC-005.md) | Export has no unrelated data; deletion request is tracked and does not destroy confirmed shared records. | backend-authorization, integration-review, live-backend |

## Limits and next action

No physical Android target or authenticated Supabase project connection is available. Real hardware/lifecycle, Auth/Storage/HTTP/realtime, full provisioning/upgrade, independent integration review and exact signed-candidate gates remain open. Supply an authorized test environment through secure tooling, run synthetic test accounts and the task scenarios, and attach sanitized results/version inventory before promotion. M2 development is explicitly authorized by the current user while dependencies remain open, but UI and server rollout must stay disabled until verified. No production deployment, public release or user-account mutation performed.
