# VER-SEC-005-LOCAL-REDACTION — local profile scrub and shared-history regression

```json verification-metadata
{
  "id": "VER-SEC-005-LOCAL-REDACTION",
  "task_ids": ["SEC-005", "QA-001"],
  "timestamp": "2026-11-05T22:25:25+08:00",
  "tested_commit": "6e57d81efabbdc3745b5420e49a819bb4e74ce6a",
  "dirty_tree": true,
  "environment": "Windows; native PostgreSQL 17.11; local PostgREST 16.5; generated synthetic accounts and self-issued JWTs; Flutter 3.47.8 / Dart 3.13.7",
  "checks": [
    {"category": "regression", "outcome": "passed"},
    {"category": "local-postgrest-integration", "outcome": "passed"},
    {"category": "local-postgresql-fresh-install", "outcome": "passed"},
    {"category": "local-postgresql-reconstructed-upgrade", "outcome": "passed"},
    {"category": "analysis", "outcome": "passed"},
    {"category": "flutter-suite", "outcome": "passed"},
    {"category": "backend-authorization", "outcome": "unverified"},
    {"category": "live-backend", "outcome": "unverified"},
    {"category": "android-device", "outcome": "unverified"}
  ],
  "commands": [
    "node .dart_tool/native-db/qa001-local-api-additional.mjs",
    "C:\\src\\flutter\\bin\\flutter.bat analyze --no-pub",
    "C:\\src\\flutter\\bin\\flutter.bat test --no-pub"
  ]
}
```

## Expected and actual results

The full local M1 HTTP harness exited successfully. PostgreSQL applied 50 migration files / 965 statements on a fresh database and 32 pending files / 493 statements on the reconstructed 18-migration baseline. The SEC-005 local HTTP assertions passed 10/10. A synthetic owned avatar, Auth-matching synthetic email, and phone were present before reviewed deletion; the counterpart's post-deletion profile returned `display_name: Former member` and null `email`, `phone`, and `avatar_url`. The counterpart retained the acknowledged shared expense and confirmed payment; the former owner's data access was denied. The local harness directly simulated Auth Admin soft-delete/session cleanup and Storage object deletion/acknowledgment.

Flutter analysis reported no issues and the full Flutter test suite passed 651/651. These Flutter checks ran on the same source tree; the only tracked worktree change was this local regression script. The script was committed after the successful local HTTP run as `241bdfd588fe0547ccde36a516c6eab5e59ba8b6`.

## Evidence

The detailed synthetic result is retained locally at `.dart_tool/native-db/qa001-exact-rehearsal-report.json` and is intentionally not committed. No live user data or credentials were used. All local Auth tokens were self-issued by the harness; service and Storage operations used the disposable local database.

## Limits and next action

This evidence does not satisfy SEC-005's live backend authorization requirement. No Supabase Auth-issued JWT, deployed Auth/Storage integration, live API mutation, physical Android device, or production change was used. Keep SEC-005 implemented and its live authorization gate open. Use an authorized disposable Supabase project and two fixture accounts for the authenticated positive/negative checks, then obtain independent review.
