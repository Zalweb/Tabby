# android-and-release implementation plan

## Purpose and current state

Permissions, lifecycle, performance, signing and candidate release evidence. Baseline code exists, but the linked findings remain open. Historical complete labels do not establish current readiness. Primary owner: **Platform/release agent**.

## Target behavior and contracts

All publishable APKs require the release certificate. Candidate verification records exact commit, digest, signing identity, package/version and environment. Build success does not authorize publishing. Preserve iOS/web behavior when shared Flutter contracts change. Read [shared contracts](IMPLEMENTATION.md#shared-contracts) and [project decisions](../project/DECISIONS.md) before changing APIs.

AND-002 implementation checkpoint (2026-10-31): account data is excluded from legacy/cloud backup and device transfer because secure-storage keys are device-bound. Android restore and invalid-key recovery still require device verification; startup's optional preference recovery does not establish full secure-storage repair. Generated Kotlin compiler sessions are ignored by Git.

AND-001 implementation checkpoint (2026-10-31): scheduled and boot receivers are declared with reboot/package-replacement broadcasts. The service requests exact-alarm access only during explicit notification permission opt-in and checks current access whenever scheduling. Denied access or the plugin's exact_alarms_not_permitted race falls back once to inexact scheduling; unrelated failures propagate. The policy is unit-tested and packaged in a debug APK. Existing reminder/preference flows still need to call the service (HOME tasks); reboot, permission/settings return, closed-app taps and delivery remain unverified on devices.

## Ordered tasks and dependencies

Task records are authoritative for state and ownership. Work in order after each dependency passes its contract acceptance.

| Task | Priority | Acceptance |
|---|---|---|
| [AND-001](../progress/tasks/AND-001.md) — Android scheduled notification integration is incomplete | P1 | Scheduled reminder fires with permission allowed/denied fallback and survives reboot appropriately. |
| [AND-002](../progress/tasks/AND-002.md) — Secure-storage backup rules are absent | P2 | Restore to another device does not crash; session/cache recover safely without exposing data. |
| [AND-003](../progress/tasks/AND-003.md) — Picker recovery and draft/back protection are missing | P2 | Kill/recreate during picker, recover image/draft; back returns a step or asks before discarding edits. |
| [AND-004](../progress/tasks/AND-004.md) — History loading and cache rewriting will scale poorly | P2 | Profile 100 tabs/10000 entries on low-memory Android; page rendering remains responsive and queue survives interrupted migration. |
| [AND-005](../progress/tasks/AND-005.md) — Automatic release can publish a debug-signed APK | P1 | Main/tag/manual publication cannot upload debug APK; installed prior release upgrades preserving data and OAuth works. |

## Verification and rollout

Add permanent regressions, run affected tests, and verify the integrated journey. Backend changes require real authenticated-role positive/negative tests and upgrade coverage, not SQL string assertions alone. Device-only behavior stays unverified until exercised. Link [verification records](../verification/README.md) from tasks; update [status](../progress/STATUS.md) using the checker.

## Migration and exclusions

Use additive versioned RPC/migration changes, preserve compatible reads and explicitly reject unsupported legacy money writes. Do not rename applied migrations or infer historical identity from names/amount similarity. Produce a reconciliation report for ambiguous history; preserve original financial records. No direct money transfer is in scope. No live deployment/publication is implied by implementation completion.

## Fail-closed Android publication gates checkpoint 2026-10-31T19:25:40.018Z

Every app release build requires configured release signing. Private candidate artifacts carry exact commit/digest/certificate/package/version and ZIP/ELF alignment metadata. Only the centralized manual main workflow can publish Android, after run provenance, full artifact reinspection and docs/releases/<commit>.json evidence checks. All M1/QA/REL tasks and exact-artifact device/backend/authorization categories must pass; only documentation may change after the candidate. Unsigned iOS artifacts are private and cannot bypass the Android release gate.

See [verification](../verification/VER-AND-005.md). No deployment; environment-specific limits remain open.

## Account-bound picker recovery and durable guarded entry drafts checkpoint 2026-11-01T14:47:35.835Z

Image picking must record owner and exact destination before native launch and retain encrypted owned bytes before acknowledging a handoff. Startup retrieves lost data; reopening the original form restores its draft/image without an upload or financial submission. Explicit discard removes form and recovered image; late account responses never update a different session. Financial draft retries preserve the same operation and immutable parties, including after an acknowledged result. Android lifecycle and secure-storage acceptance remain required.

See [verification](../verification/VER-AND-003.md). No deployment; environment-specific limits remain open.

## Restore recovery source checkpoint

The startup gate probes encrypted ledger storage before mounting providers or queue writers. A read/unlock failure blocks private content and offers a non-destructive retry. On Android, an explicit recovery confirmation plus fresh device authentication can preserve encrypted ledger/WAL/SHM and secure-preference ciphertext/wrapped keys in a private `noBackupFilesDir/storage-recovery/<random-id>` directory before resetting those originals. No recovery copies are auto-imported or queued for replay. Cloud history and Android Keystore aliases are untouched. Recovery requires closing and reopening the process because plugins cache encryption state. Unsynced entries/drafts can remain unrecoverable without original keys; the UI discloses this before confirmation. Backup/transfer exclusions remain enabled. Physical restore, interrupted archive/reset and device-authentication checks remain unverified. See [AND-002](../progress/tasks/AND-002.md).

## Bounded history and storage integration

[AND-004](../progress/tasks/AND-004.md) now uses authenticated UUID pages (100 headers / 200 financial rows) and batched balances (100 tabs) instead of embedded unbounded history and per-tab balance requests. Complete ID-reconciled histories are assembled before publication for accurate group obligations; page reads are current reads and may include concurrent revisions on a later refresh. A failed page does not publish a partial ledger. History rendering reveals 50 records at a time. Native cache and queue use encrypted transactional Drift with atomic legacy import and secure-storage keys; compatibility JSON encoding/decoding runs outside the UI isolate. The indexed database page API remains available. Low-memory Android profiling, actual runtime encryption and interrupted migration remain device gates. See [verification](../verification/VER-AND-004-IMPLEMENTATION.md).

## Paired mobile release automation — 2026-11-18T21:31:28+08:00

Supersedes the earlier manual-only publication checkpoint for routine delivery. A successful same-repository `main` mobile workflow run contains the private release-signed Android APK and unsigned arm64 IPA. The publisher re-fetches that exact run's two artifacts, repeats Android signature/certificate/digest/package/version/ZIP/ELF checks, confirms the iOS source commit, digest, package, shared version, arm64/unsigned report and passed simulator evidence, and runs the unchanged `docs/releases/<commit>.json` production-evidence gate. Build, tag, event input or artifact metadata alone cannot authorize publication.

The reconciler is awakened by mobile-build success, release-evidence/task-record pushes and a daily schedule. It only selects the latest successful push build from the same repository's `main`; fork, PR, tag, failed and manual runs are excluded from automatic publication. A candidate may use a documentation-only descendant, as allowed by the existing release gate. The protected `android-release` environment remains after the automated checks; a configured reviewer is a public release approval. The old manual entry point is retained for exceptional recovery and invokes the same guard with an exact run ID and commit.

Both Android and main iOS read `version_name` and `version_code` from `pubspec.yaml`. The previously published `1.0.4+24` therefore advances to `1.0.4+25`; do not use the former `+5` value. Bump the shared build number beyond every published release before producing different public app bytes. Existing tags with different bytes and older build codes fail closed. APK and IPA are uploaded to an unpublished draft, both GitHub asset digests are checked against the verified files, and only then is the complete pair made latest. Partial builds/uploads leave the current published release untouched.

For current main builds, `ios-prepare.py` first verifies a clean tracked checkout at exact `GITHUB_SHA`, then generates a temporary manifest from tracked repository inputs. The generated manifest and packaging report travel only with the private artifact. Frozen `ios/build-source-manifest.json` verification remains available for historical/frozen candidates. Reuse of simulator proof still requires a successful actual prior simulator step and exact matching native/app input hashes; any changed native input forces fresh simulator checks. See the [paired publication contract](../releases/README.md), [iOS sideload guide](../project/IOS_SIDELOAD.md) and [current REL-001 evidence](../verification/VER-REL-001-LOCAL-CANDIDATE.md).

The hosted Android signing secrets and iOS public client hashes remain the previously recorded blockers. This automation does not mark the environment, candidate evidence, authorization, physical device, backend or release gates complete.


## Native callback ownership — 2026-11-17T10:29:05.386Z

Android Flutter default URL handling is disabled because app_links owns OAuth and the account-bound native push channel owns reminder taps. PendingIntent URI remains unique identity, never an arbitrary navigation route. Native onNewIntent leaves payload extras pending until Dart requests initialTap after installing its listener; consume under the current binding, then wait for authenticated server authorization and exact target data before navigation. [Actual warm/cold evidence](../verification/VER-QA-027-NATIVE-INTENTS.md).
