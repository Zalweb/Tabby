# REL-003 landing fallback validation

```json verification-metadata
{
  "id": "VER-REL-003-LANDING",
  "task_ids": ["REL-003"],
  "tested_commit": "8e5a139780bedd8ebdad4203726fec8edfe9e007",
  "dirty_tree": true,
  "timestamp": "2026-11-18T18:20:00+08:00",
  "environment": "Windows 10.0.26300; Playwright 1.56.1 headless Chromium (chrome-headless-shell 1254) at desktop viewport; Node 26; live Vercel site https://tabby-web-fawn.vercel.app and GitHub Releases API",
  "checks": [
    {"category": "local-regression", "outcome": "passed"},
    {"category": "browser-ui", "outcome": "passed"},
    {"category": "release-artifact", "outcome": "passed"},
    {"category": "static-fallback-deploy", "outcome": "passed"},
    {"category": "mobile-browser", "outcome": "unverified"},
    {"category": "full-download", "outcome": "unverified"}
  ],
  "commands": [
    "node test/web_landing_test.js",
    "CHROME_PATH=.../chrome-headless-shell.exe node check-live.mjs https://tabby-web-fawn.vercel.app/ live-before.png",
    "curl -sS -o /dev/null -D - -H 'Accept: application/octet-stream' https://github.com/Zalweb/Tabby/releases/download/v1.0.4%2B24/Tabby-v1.0.4%2B24.apk",
    "curl -sS -o /dev/null -D - -H 'Accept: application/octet-stream' https://github.com/Zalweb/Tabby/releases/download/v1.0.4%2B24/Tabby-v1.0.4%2B24.ipa"
  ]
}
```

## Expected and actual results

Tested content: `origin/main` at `8e5a139780bedd8ebdad4203726fec8edfe9e007` plus the uncommitted REL-003 fallback edits (32 insertions / 32 deletions across the four mirrored files); the task/verification records themselves are also untracked, hence `dirty_tree: true`. Tested before the change was committed or deployed.

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

## Limits and next action

The browser passes verify the rendered live state and the download redirect targets, not a complete byte-for-byte download through the UI. No physical mobile browser was used; the corrected static text is directly present in the served HTML, so the no-JavaScript case is covered by content inspection rather than a JS-disabled browser pass. No further action is required for this fallback update; any future release changes the shared rendering path and should repeat these checks.

## Deployment

Confirmed in production at `https://tabby-web-fawn.vercel.app/` from commit `997dca6` (see the post-deploy confirmation above). No other deployment surface changed.
