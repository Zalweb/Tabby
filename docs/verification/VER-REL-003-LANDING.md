# REL-003 landing fallback validation

```json verification-metadata
{
  "id": "VER-REL-003-LANDING",
  "task_ids": ["REL-003"],
  "tested_commit": "8ee6b972de8d85afd8889541e8cdb5e4ec500e91",
  "dirty_tree": false,
  "timestamp": "2026-11-18T19:03:00+08:00",
  "environment": "Windows 10.0.26300; Playwright 1.56.1 headless Chromium (chrome-headless-shell 1254) at desktop viewport; Node 26; Python 3 ios-prepare/ios-build-tests; live Vercel site https://tabby-web-fawn.vercel.app, GitHub Releases API and GitHub Actions API",
  "checks": [
    {"category": "local-regression", "outcome": "passed"},
    {"category": "browser-ui", "outcome": "passed"},
    {"category": "release-artifact", "outcome": "passed"},
    {"category": "static-fallback-deploy", "outcome": "passed"},
    {"category": "source-manifest", "outcome": "passed"},
    {"category": "integration-review", "outcome": "passed"},
    {"category": "ci-ios", "outcome": "failed"},
    {"category": "mobile-browser", "outcome": "unverified"},
    {"category": "full-download", "outcome": "unverified"}
  ],
  "commands": [
    "node test/web_landing_test.js",
    "CHROME_PATH=.../chrome-headless-shell.exe node check-live.mjs https://tabby-web-fawn.vercel.app/ live-before.png",
    "curl -sS -o /dev/null -D - -H 'Accept: application/octet-stream' https://github.com/Zalweb/Tabby/releases/download/v1.0.4%2B24/Tabby-v1.0.4%2B24.apk",
    "curl -sS -o /dev/null -D - -H 'Accept: application/octet-stream' https://github.com/Zalweb/Tabby/releases/download/v1.0.4%2B24/Tabby-v1.0.4%2B24.ipa",
    "python scripts/ios-prepare.py --verify-source",
    "python scripts/ios-build-tests.py",
    "gh run view 44284627274 --log-failed (failure attribution)"
  ]
}
```

## Expected and actual results

Tested in stages: initial checks against `origin/main` at `8e5a139780bedd8ebdad4203726fec8edfe9e007` plus the uncommitted fallback edits (dirty tree); post-deploy checks on `997dca6`; review on `e3a39a5`; and manifest-refresh plus final checks on `8ee6b972de8d85afd8889541e8cdb5e4ec500e91` (clean tree; metadata reflects this final commit). The landing files are byte-identical from `997dca6` through `8ee6b97`; only records and `ios/build-source-manifest.json` changed after deployment.

- `node test/web_landing_test.js` passed every assertion, including strict byte equality of `landing/index.html` ↔ `docs/index.html`, `landing/app.js` ↔ `docs/app.js`, the simulated release rendering, and a live `200` status check of the production URL.
- Rendered live page before deployment (headless Chromium, network idle plus explicit wait for version tags): release engine applied; all six `[data-role="version-tag"]` pills read `v1.0.4+24`; release date read `November 18, 2026`; APK size read `70.2 MB`; APK filename read `Tabby-v1.0.4+24.apk`; live-status badges read `Latest Build: v1.0.4+24 (Live)`; changelog body contained the published release notes; no console errors or page errors were observed.
- Button targets: both APK buttons resolved to `https://github.com/Zalweb/Tabby/releases/download/v1.0.4%2B24/Tabby-v1.0.4%2B24.apk` and both IPA buttons to the matching `.ipa` URL. Unfollowed `HEAD` requests returned `302` with `content-disposition` filenames `Tabby-v1.0.4+24.apk` (73,609,244 bytes) and `Tabby-v1.0.4+24.ipa`, confirming the buttons point at the published `v1.0.4+24` assets rather than the older release.
- Raw served HTML before deployment: all seven static version strings read `v1.0.3`, with `Tabby-v1.0.3.apk`, `74.8 MB` and `September 19, 2026` — the defect fixed by this task. After the edits the worktree copies contain `v1.0.4+24`, `Tabby-v1.0.4+24.apk`, `70.2 MB` and `November 18, 2026`, with no remaining `v1.0.3` or `74.8 MB` occurrences.

## Evidence

Transcript JSON output from the browser run (version tags, hrefs, sizes, dates, changelog present, HTTP statuses, redirect targets) and a desktop screenshot `live-before.png` captured outside the repository in the temporary verification directory. `test/web_landing_test.js` printed its full pass output. Screenshot is not committed (contains no private material but is redundant with the recorded values).

## Post-deploy confirmation

2026-11-18T18:20:00+08:00 — Commit `997dca6` was pushed from `8e5a139` to `origin/main`. The Vercel production deployment picked it up before the second poll (about 15 seconds after the push). Served HTML and script now carry the corrected fallback:

- `https://tabby-web-fawn.vercel.app/` returns `200`; raw HTML contains `0` occurrences of `v1.0.3`, `Tabby-v1.0.3.apk`, `74.8 MB` and `September 19`; it contains `v1.0.4+24` ×7, `Tabby-v1.0.4+24.apk` ×1, `70.2 MB` ×2 and `November 18, 2026` ×2.
- Served `app.js` defaults now read `v1.0.4+24`, `70.2 MB` and `November 18, 2026` (five matching lines).
- Rendered page re-checked in headless Chromium after deployment: HTTP `200`, release engine applied, all six version pills `v1.0.4+24`, three APK links and one IPA link to the versioned GitHub assets, sizes `70.2 MB`, filename `Tabby-v1.0.4+24.apk`, dates `November 18, 2026`, live badges `Latest Build: v1.0.4+24 (Live)`, changelog populated from the release body, and no console errors. Both asset URLs returned `302` with `attachment` content-disposition filenames `Tabby-v1.0.4+24.apk` and `Tabby-v1.0.4+24.ipa`.
- Post-deploy screenshot `live-after.png` captured next to `live-before.png` in the temporary verification directory.

## Review and remediation

2026-11-18T18:46:00+08:00 — User-requested review pass over both commits, the records and production. The reviewer used the same Qoder session as the authoring handoff (recorded as Qoder desktop / Codex continuation), so this is an adversarial re-verification of committed artifacts rather than a separate-agent or organizational review.

- Re-confirmed scope: the diff contains only fallback values and records; `landing/` ↔ `docs/` mirrors are byte-identical; the secret-pattern scan over the diff found nothing; the latest GitHub release is still `v1.0.4+24` with APK 73,609,244 bytes (`sha256:006c2cff…`) and IPA 31,633,412 bytes (`sha256:c5558cd4…`); production still serves the updated fallback.
- The push-triggered iOS run `44284627274` failed `Verify source and configure CocoaPods` with `Candidate source does not match its frozen manifest: docs/INDEX.md`. Audit of all 952 `ios/build-source-manifest.json` entries: 946 matched, 6 stale (`docs/INDEX.md`, `docs/app.js`, `docs/index.html`, `docs/progress/STATUS.md`, `landing/app.js`, `landing/index.html`), none missing. Refreshed exactly those six documentation/landing hashes; `python scripts/ios-prepare.py --verify-source` reports `Frozen source hashes verified: 952`, and `python scripts/ios-build-tests.py` passes 9/9, including the fixture asserting that documentation/packaging changes must not alter native reuse inputs. No app, native, asset, dependency or client-config hash changed.
- The Android job fails at `Configure Android release signing` on this commit and on base `8e5a139`; this is a pre-existing signing-secret failure owned by the release-signing workflow, not a REL-003 change.

CI confirmation on `8ee6b97` (run `44289031790`, push to `main`): the Project memory workflow passed; the iOS `Verify source and configure CocoaPods` step passed, confirming the manifest refresh fixed the earlier failure. The iOS job then failed later in `Prepare client configuration and native OAuth` with `Client configuration differs from the reviewed Android/backend candidate` (`scripts/ios-prepare.py:72`). Attribution shows this is external to REL-003:

- `TABBY_IOS_BUILD_CONFIG` was updated at `2026-11-18T09:15:23Z`.
- The base main run `44210852625` started at `00:48:38Z`, before the rotation, and passed that step against main's staging hashes.
- Production-branch run `44274221017` started at `09:15:28Z`, passed the same step and the whole job against the branch's reviewed production hashes (`ios/client-config-hashes.json` sha256 `28b280d1…`).
- Main's `ios/client-config-hashes.json` is unchanged since the base commit (sha256 `74a2be51…`) and REL-003 touches neither it nor the comparison logic, so any main push after the secret rotation fails here until main adopts the reviewed production binding (REL-002/QA-034 follow-up).

## Limits and next action

The browser passes verify the rendered live state and the download redirect targets, not a complete byte-for-byte download through the UI. No physical mobile browser was used; the corrected static text is directly present in the served HTML, so the no-JavaScript case is covered by content inspection rather than a JS-disabled browser pass. The iOS source-verification regression is confirmed fixed; the remaining iOS job failure is the external client-config snapshot mismatch described above, not a REL-003 acceptance check. The Android signing failure is pre-existing on `main` and outside REL-003. All REL-003 required checks pass. Adopting the reviewed production client configuration on `main` remains a REL-002/QA-034 follow-up. No further action is required for this fallback update; any future release changes the shared rendering path and should repeat these checks.

## Deployment

Confirmed in production at `https://tabby-web-fawn.vercel.app/` from commit `997dca6` (see the post-deploy confirmation above). No other deployment surface changed.
