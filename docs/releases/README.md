# Paired Android and iOS release contract

Mobile build runs on `main` create private Android and unsigned iOS artifacts from the same GitHub run and source commit. A successful build does not publish an app or authorize release.

## Candidate evidence

Before publication, add `docs/releases/<candidate-commit>.json` on a documentation-only descendant of the candidate. The existing `scripts/check-release-gate.cjs` must pass for that exact signed Android APK. All M1 tasks, QA-001 and REL-001 must be complete. Required checks are regression, analysis, integration, backend-integration, android-device, upgrade, oauth, 16kb-device, release-artifact and release-authorization.

Every referenced verification record must match the candidate commit and APK digest/certificate, record `dirty_tree: false`, name the actual environment and pass its category. Physical device upgrade/data preservation, OAuth, a 16 KB runtime, applied migration inventory, live backend authorization and existing release authorization remain required; ZIP/ELF inspection cannot replace them.

The paired publisher also rechecks the unsigned iOS IPA from that exact successful main build run. It requires the report and IPA bytes to agree on source commit and SHA-256, `com.zalweb.tabby`, the same version name/build number as Android, arm64 architecture, unsigned output and passed iOS simulator evidence. Its tracked source manifest must identify the exact build commit. The Android signature, certificate, package/version, ZIP/ELF alignment, candidate JSON, evidence categories and documentation-only descendant are independently rechecked before publication and again after release approval.

## Automatic publishing and recovery

The reconciliation workflow runs after successful main mobile builds, when release evidence changes on `main`, and on a daily schedule. It selects the newest successful same-repository `main` push build whose commit-keyed `docs/releases/<commit>.json` review file exists in the trusted `main` checkout, then confirms both platform artifacts came from that run and applies the exact candidate gate above. A newer successful build without its own reviewed evidence does not shadow an older eligible candidate; if no matching evidence exists, publication is skipped cleanly. Pull request, tag, fork, failed or manual build events cannot enter automatic publication. Evidence added after a build is picked up by the next qualifying evidence push or scheduled reconciliation while that build's private artifacts are retained.

Eligible assets are uploaded as `Tabby.apk` and `Tabby.ipa` to a draft. The publisher checks both GitHub asset digests against the verified artifact bytes before marking that draft as the public latest release. If a build, check or upload fails, the current published release remains available. Existing tags with different bytes, older version codes and mismatched tag targets cannot replace a release. Re-running the same exact release is idempotent.

The protected `android-release` GitHub environment remains in the path. Any required reviewer is approving the public release after the candidate checks; no separate manual publication dispatch is required for normal delivery. `Publish Release APK` remains a recovery entry point only and invokes this same guarded paired publisher with an exact run ID and commit.

## Shared version source

`pubspec.yaml` is the single app version source for Android and main-branch iOS builds. The previously published version is `1.0.4+24`; this branch raises the next shared build number to `1.0.4+25` rather than allowing the old `pubspec.yaml` value `1.0.4+5` to roll back users. Before the next public app release, bump the semantic version/build number in `pubspec.yaml`; build numbers must increase beyond every published release. Rebuilding changed app bytes under an already published tag fails closed. Documentation-only commits keep the version unchanged.

## iOS source manifests

Main builds verify that the checked-out tree is clean and exactly matches `GITHUB_SHA`, then generate a temporary manifest of all Git-tracked inputs for the IPA report and packaging checks. The generated manifest is stored with the private build artifact and is not committed or exposed in the release. `ios/build-source-manifest.json` remains the explicit frozen source check for historical candidates and deliberate frozen-source builds; ongoing main builds do not require manual hash edits after every docs or landing change.

Native simulator evidence is reused only when the prior successful simulator run is verified through GitHub Actions and the exact hashes of native/app inputs match. Otherwise, the iOS simulator checks run on the current build and record evidence for that commit. A docs-only change can reuse proof when all simulator inputs are unchanged; it cannot convert source inspection into simulator evidence.

## Hosted configuration and remaining gates

The iOS public-client hash snapshot is copied from reviewed commit `921e22779fad45144be16fad265dcd7643122aee`; GitHub run `44274221017` passed client configuration, native smoke and IPA packaging with that same release configuration. Main run `44291911273` predates this correction and failed client-hash verification as well as Android signing configuration. Hosted CI must still confirm the checked-in public hashes against the current protected configuration. Configure Android release signing secrets and the `ANDROID_RELEASE_CERT_SHA256` repository variable without storing keys/passwords in Git. Keep `android-release` protected on `main` with its required release reviewers. Android signing and reviewer authorization remain hosted prerequisites; this automation does not bypass them. The current REL-001, QA-001, mobile/device, authorization and release-evidence records remain authoritative.

Build artifacts are private and retained for up to 90 days to cover delayed evidence review. No candidate file may be synthesized from mocks, debug-signed APKs or source-only inspection. The unsigned IPA is not an App Store/TestFlight release; users must sign it with Sideloadly using their own Apple account. No backend rollout or money movement is included.
