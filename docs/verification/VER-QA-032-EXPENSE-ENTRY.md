# QA-032 — Existing tabs, duplicate guidance and custom amounts

```json verification-metadata
{
  "id": "VER-QA-032-EXPENSE-ENTRY",
  "task_ids": [
    "QA-032"
  ],
  "timestamp": "2026-11-17T19:31:49.240Z",
  "tested_commit": "b840c44f94a01521eb1fb624a9ba99edbc718c8e",
  "dirty_tree": true,
  "environment": "Windows Flutter3.47.8/Dart3.13.7; native PostgreSQL17.11/PostgREST16.5 local fixtures; Lenovo TB321FU API36 ARM64 4KB native16 cases; exact signed universal1.0.4+22 on tablet and native x86_64/16KB emulator",
  "commands": [
    "flutter test --no-pub --reporter expanded",
    "dart analyze --fatal-infos lib test integration_test",
    "node scripts/test-backend-native.cjs",
    "local full-migration PostgREST acceptance with scripts/local-m1-http-regressions.mjs",
    "node scripts/usb-test.cjs --suite expense-entry",
    "node --test scripts/usb-test.test.cjs"
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
      "category": "backend-integration",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    }
  ]
}
```

## Implemented contracts

- Read-only registered pair lookup uses both immutable IDs and recognizes either actor ordering. Active empty tabs count. Network failure, unavailable/archived or ambiguous identity is not reported as a new relationship. Group creation is explicit and does not redirect into a member's bilateral ledger.
- Existing-tab dialog uses the requested title, message and Add New Expense/View Existing Tab/Cancel actions with PHP amount and viewer-relative direction. Selection/view/cancel have no financial writer. Add retains the exact selected tab ID; provider keeps that ID separate from the financial counterpart/payer ID. Old named contacts remain distinct IDs.
- Duplicate hint compares tab, integer total, normalized description, category, payer, allocation and recorded local calendar date. It excludes payments, cancelled/superseded/reversal rows and the current operation. Review is read-only. Add Anyway authorizes only the unchanged visible draft; it preserves the stable command ID. Matching amounts alone do not warn.
- Custom amounts are integrated into existing Create/Add forms with zero-share payers, immutable roster IDs, exact-sum validation and encrypted draft persistence. The existing M1 explicit-participant contract independently validates these allocations. No schema/history migration or advanced M2 tax/service rollout is needed.
- Repeated taps are disabled before async work. Frozen attempted drafts retry the same operation and return to Details on reopen; confirmed results and pending/attention outcomes are distinguished. Backend-derived ledger refresh precedes a new expense; failed history refresh blocks that new save. Existing serialized queue, conflict checks and server operation idempotency remain authoritative.

## Expected and actual results

| Requested scenario | Evidence and boundary |
| --- | --- |
| No existing shared tab | Flutter/physical form fixture continues Create without writes; HTTP pair lookup returns empty before seeded relationships. |
| Existing shared tab | Exact form dialog and direction checks, including empty and settled balance, plus read-only HTTP identity query. |
| Opposite account | Both independently authorized local HTTP readers see the identical tab ID and transactions; transport test exercises both actor orders. |
| Genuine second same-amount loan | Different description saves normally; deliberate same-description Add Anyway appends one new operation. HTTP balance moves +15000/-15000 to +30000/-30000. |
| Accidental duplicate | Full fingerprint warning, Review/Cancel leave count and balance unchanged. No amount-only uniqueness constraint. |
| Cancel existing-tab confirmation | Selection remains uncommitted, count and balance unchanged in three debt directions. |
| Rapid Save taps | Actual form fixture and eight parallel HTTP retries of one operation yield one record. |
| Response loss/retry | Form draft reopen retains original operation; HTTP deliberately discards first response and replays it; hydrated server participant representation also has a dedicated regression. |
| Two-user synchronization | Actual local PostgREST reads under separate signed test tokens see the same persisted rows and opposite balances. This is not a Google authentication or Realtime websocket assertion. |
| Correct confirmed balance | Native SQL and HTTP independently calculate saved ledger balances; custom group returns +45000/-15000/-30000. |

Additional cases cover exact cents/roster and allocation errors, historical-tab exact ID, two-member group payer, unchanged bilateral ledgers during new custom group creation, session disposal, dialog removal on account change, manual contact identity and encrypted SQLite close/reopen.

## Evidence

The initial pure-policy test failed because the implementation was absent, then all four cases passed. Explicit superseded/reversal candidates reproduced a false warning and were excluded. Exact chosen-tab identity and a two-member group payer each had failing provider regressions before repair.

First full root run had 867 passes and seven failures: obsolete create/duplicate labels and currency test text corrupted by a PowerShell encoding round trip. Text was restored using UTF-8 and tests were updated for the requested Add/Review actions, retaining financial assertions. The next root suite passed 874, then 877 after identity/session cases; frozen source later passed 878. These counts describe successive sources, not one final candidate.

Initial Android form attempts disclosed two fixture faults: mock secure keys combined with persistent native SQLite across runs, and the real Android IME echoing its previous151 over WidgetTester-injected150. The suite now explicitly mocks form storage/text injection, and a separate process/target exercises real encrypted native SQLite and Android secure storage. The first native storage assertion used an unrelated viewer scope and therefore recomputed zero; using the actual payer scope proved45000 on reopen. No failed run is claimed as a pass.

The final pre-review device run passed14 form cases plus1 separate native-storage case, with the runner requiring every named case;11 runner guards pass. Six light/dark previews were rendered and visually inspected. Subsequent final review found an acknowledged bilateral retry comparing hydrated participant rows with an intentionally empty local bilateral list; the old frozen source reproduced the StateError and the new regression passes after retaining bilateral summary comparison and full group roster comparison. A fresh frozen suite/device run is required for that last repair.

## Limits and next action

No production SQL, original transactions, balances, registration settings, background scheduler or public release changed. Tablet main19 and spare USB-test app/session are preserved during isolated fixtures. Signed normal20 packaging/installed-byte evidence is pending. Independent integration review, real two-device Realtime acceptance, iOS and screen-reader checks remain open; successful local/device checks do not establish general production approval.


2026-11-17T18:55:00.494Z — Final superseding evidence: frozen879/879 cases, fatal-info analysis and final physical14 controlled form +1 real encrypted-storage cases pass after the hydrated-ACK repair. Source211 hashes and test150 hashes remain fixed. Universal nondebuggable1.0.4+20 APK SHA256 febe8741a8ec8996eb8916ef1ed2d836965a591f67626bbd168631a26e41e75d passes approved production certificate, ZIP and ELF16KB checks. Exact bytes installed19→20 on physical tablet without logout, uninstall, clear or financial seed; original firstInstallTime and spare .usbtest preserved, temporary .entrytest removed. Launch/process and scoped fatal/loader checks pass. The exact same APK installed18→20 and launched on the owned native x86_64/16KB emulator; Google welcome observed, no authenticated emulator journey inferred. Owned emulator shutdown completed. Native/build/device reservation RELEASED, next normal21+. Prior pending/install/final-repair statements above are dated history superseded here. No public/backend release or independent/general production approval. [Sanitized results](QA-032-results.json), [source manifest](QA-032-source-manifest.json).

2026-11-18T03:05:54.0240278+08:00 - Additional post-delivery edge: the existing-tab check exempted forms initially opened with a tab ID, so switching to another registered person inside Add could bypass confirmation. The specific new test failed on20 behavior; removing the two initialCounterpartId exemptions gives15/15 current form cases and clean analysis. Expense native contract now requires15 form +1 real-storage cases for the next run. This extra case is NOT part of installed20's15-case evidence. Root patch/contract awaits subsequent native/candidate delivery;20's source manifest and installed bytes remain unchanged.

2026-11-18T03:19:50.0166443+08:00 - SDK transport extension:12 actual repository/SDK request cases cover registered user/contact, either payer and viewer shares0/15000/45000 of45000. Two cases reproduced a doubled allocation for zero remaining when the other party paid and owned the whole bill. Replacing fallback payer allocation with exact0 gives12/12. A synthetic HTTP transport validates payload sum and records IDs/roles; this does not assert real Auth or deployed SQL. The existing independent PostgreSQL/PostgREST contract checks remain separate. No queued command or confirmed history is rewritten; final22 composition will include this narrowly scoped repair before any signed22 build.


2026-11-17T19:31:49.240Z — FINAL22 supersedes the earlier20/21 pending-fix checkpoints. Full903/903, clean fatal-info analysis,39 isolated expense regressions,12 SDK wire cases and final15 controlled form +1 real encrypted-native-storage cases pass. Signed nondebuggable universal1.0.4+22 SHA256 2c007275b283361fc647b1c48e8c72dafd2b2b57db1a90a5c921bcc27495502a passes approved certificate and ZIP/ELF16KB checks; exact bytes installed21→22 on the physical tablet. FirstInstallTime/login/data and .usbtest retained, no logout/clear/uninstall/financial seed; temporary .entrytest removed, launch/process/no scoped fatal-loader errors. Exact same22 APK installed20→22 and launched on native x86_64/16KB emulator: Google welcome/process/no fatal-loader errors; no authenticated emulator journey inferred. Owned emulator shut down. Native/build/device reservation RELEASED, next normal23+. Source218 hashes preserve every accepted21 app/art file except the two reviewed expense files. Follow-ups are delivered; advanced M2 flags/history/backend/public release unchanged. Independent review and real two-device Realtime remain open. [Final source](QA-032-v22-source-manifest.json), [results](QA-032-results.json), [user change summary](../plans/expense-entry-update-summary.md).
