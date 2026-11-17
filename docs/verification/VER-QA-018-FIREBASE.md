# QA-018 — Firebase sign-in and project-quota setup blocker

```json verification-metadata
{
  "id": "VER-QA-018-FIREBASE",
  "task_ids": [
    "QA-018"
  ],
  "timestamp": "2026-11-14T14:20:41.074+08:00",
  "tested_commit": "734d80093c1a340c87eab1b2b3b5303372e63319",
  "dirty_tree": true,
  "environment": "Official firebase-tools15.36.0 on Node26/Windows; manually authenticated Google account; no Firebase project mutation",
  "commands": [
    "firebase login --interactive",
    "firebase projects:list --json",
    "firebase projects:create tabby-android-7abf436e --display-name Tabby --json",
    "official Firebase management API available-project inventory"
  ],
  "checks": [
    {
      "category": "provider-configuration",
      "outcome": "unverified"
    },
    {
      "category": "android-push",
      "outcome": "unverified"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    }
  ]
}
```

## Expected and actual results

Installed the official isolated CLI and ignored Firebase logs/cache/private SDK material. Headless links were rejected by Google; direct interactive Google OAuth with localhost callback succeeded after user completed sign-in. Gemini and telemetry declined. Project creation was denied by Google Cloud because account project quota was exhausted. Existing Firebase/available GCP inventory has no named Tabby project. Asked user for an explicitly unused existing project ID; no unrelated project chosen or deleted.

Successful standard Google login verified by authenticated project listing. Creation returned RESOURCE_EXHAUSTED/code8: allotted project quota exceeded. Rejected remote login links retained as failed attempts; no auth codes/tokens in shared records. Final74 Node checks and analysis recorded separately. Windows browser/native automation unavailable; Google authentication completed manually.

## Evidence

[Sanitized current results, artifacts, source delta and log digests](QA-018-results.json). Tested source is base 734d80093c1a340c87eab1b2b3b5303372e63319 plus the recorded dirty-tree delta. No Firebase project created, app registered, billing attached, provider credential deployed or scheduler enabled. Approved Azure security patch is documented separately in QA-017.

## Limits and next action

Waiting for a designated unused existing GCP project or a quota increase. Verify billing disabled before adding Firebase; Spark/no billing is mandatory. Android app/signature registration, public build defines, private sender credentials and actual device FCM acceptance remain unrun. No Firebase configuration should be reported complete.

User names an unused project ID or increases quota; inspect billing read-only, then continue the already authorized free Firebase setup and actual Android push checks.

2026-11-14T14:24:28.664+08:00 — Checkpoint validation: final analysis clean;74 Node and4 Python guard checks pass, Python syntax passes. Project memory write/plain/base checks pass at72 tasks/45 findings/94 verification records. Targeted credential/path scan found0 issues across43 owned files. Staged archive validates without ignored live configuration or build artifacts. Diff whitespace passes. Independent integration review and release gates remain open.

2026-11-17T07:04:59.293Z — Read-only follow-up: existing CLI authentication works, zero Tabby-named Firebase projects found; prior candidate billing remains disabled/unattached. [Current sanitized inventory](QA-018-inventory-20261117.json). No repeated project-create attempt or cloud mutation; awaiting owner-selected unused project. Earlier quota result is dated evidence, not a new failed create.
