# WEB-002 landing page and paired download verification

```json verification-metadata
{
  "id": "VER-WEB-002-LANDING",
  "task_ids": ["WEB-002"],
  "timestamp": "2026-11-18T22:28:00+08:00",
  "tested_commit": "adb4662babb188aded797ddfd3a7a1d835676f38",
  "dirty_tree": true,
  "environment": "Isolated Windows worktree, Node 26, Python 3.12, headless Brave/Chromium and current public GitHub release endpoints",
  "commands": [
    "node test/web_landing_test.js",
    "node --test test/release_workflow_test.js scripts/android-release.test.cjs",
    "python scripts/ios-build-tests.py",
    "Parse five workflow YAML documents with PyYAML and compile eight GitHub Script blocks in Node",
    "Playwright/Brave desktop, mobile and no-JavaScript checks",
    "HTTP HEAD for both stable GitHub download aliases"
  ],
  "checks": [
    {"category": "regression", "outcome": "passed"},
    {"category": "browser-layout", "outcome": "passed"},
    {"category": "release-sync", "outcome": "passed"},
    {"category": "integration-review", "outcome": "passed"},
    {"category": "deployment", "outcome": "unverified"},
    {"category": "hosted-release", "outcome": "unverified"}
  ]
}
```

## Expected and actual results

The landing regression passed and the five landing and legal files match byte for byte in both published source trees. The release tests passed 24 cases and the iOS source and packaging tests passed 13 synthetic cases. Five workflow documents parsed and eight embedded GitHub scripts compiled.

Headless Brave rendered 1440, 390 and 320 pixel widths with no horizontal overflow, broken section links, incomplete images or page exceptions. Navigation from Privacy and Terms resolves to existing landing sections. The three feature mascot animations from the intervening main update still run on entry. At 390 pixels with scripts disabled, the gallery loaded and both platform links used the stable GitHub aliases. Public HTTP HEAD requests to the APK and IPA aliases returned 302. GitHub lists both aliases on public release v1.0.4+24.

The independent release review found and corrected three gaps. Reconciliation now finds an evidence-backed older build after a newer unreviewed build. Publication compares the actual file SHA-256 digests before promoting a paired draft. Preexisting tags are resolved to their actual Git commit and an untagged draft must identify the exact candidate commit.

## Evidence

The browser reported zero overflow and no unresolved image or anchor targets at each tested width. Browser captures are in the ignored `.dart_tool/minimal-landing-evidence/` directory of the coordinator checkout. Fixture programs and hosted run identifiers are linked from [WEB-002](../progress/tasks/WEB-002.md).

## Limits and next action

The platform artifact checks used fixtures locally. Android CI signing and exact public release acceptance are still required for the first hosted release. Main previously failed iOS configuration because the pin lagged the already-rotated secret. The updated public hashes match the prior successful production iOS build recorded in REL-003. Live website deployment verification follows successful integration with current main.

