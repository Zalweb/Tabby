# REL-003 landing fallback validation

```json verification-metadata
{
  "id": "VER-REL-003-LANDING",
  "task_ids": ["REL-003"],
  "tested_commit": "8e5a139780bedd8ebdad4203726fec8edfe9e007",
  "dirty_tree": true,
  "timestamp": "2026-11-18T18:18:00+08:00",
  "environment": "Windows 10.0.26300; Playwright 1.56.1 headless Chromium (chrome-headless-shell 1254) at desktop viewport; Node 26; live Vercel site https://tabby-web-fawn.vercel.app and GitHub Releases API",
  "checks": [
    {"category": "local-regression", "outcome": "passed"},
    {"category": "browser-ui", "outcome": "passed"},
    {"category": "release-artifact", "outcome": "passed"},
    {"category": "static-fallback-deploy", "outcome": "unverified"},
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

## Limits and next action

The browser pass verifies the JavaScript-applied live state and the download redirect targets, not a complete byte-for-byte download through the UI. No mobile browser, JavaScript-disabled device, or post-deploy served-HTML check had run at this timestamp. Next: deploy the fallback edits to production and confirm the served HTML and rendered page, appended below.

## Deployment

Not yet confirmed at this timestamp. The change is committed on `main`, whose Vercel production deployment serves the tested URL; post-deploy evidence is appended when available.
