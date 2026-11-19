# QA-051 - Scoped first-launch review branch

```json verification-metadata
{
  "id": "VER-QA-051-FIRST-LAUNCH",
  "task_ids": ["QA-051"],
  "timestamp": "2026-11-19T14:16:50+08:00",
  "tested_commit": "deec6e5d518ebf7c5e04819fbc1d5b2781130f6c",
  "dirty_tree": true,
  "environment": "Isolated Windows review worktree based on current main, Flutter 3.47.8, Dart 3.13.7",
  "commands": ["flutter pub get --offline --enforce-lockfile", "flutter test --no-pub --concurrency=2 --reporter expanded test/features/startup_gate_test.dart test/features/registration_flow_test.dart test/features/registration_routing_test.dart test/features/auth_onboarding_test.dart test/features/login_layout_test.dart test/features/e2e_all_screens_buttons_test.dart", "dart analyze --fatal-infos on all production and focused test files in the scoped port"],
  "checks": [{"category": "regression", "outcome": "passed"}, {"category": "analysis", "outcome": "passed"}, {"category": "android-device", "outcome": "unverified"}, {"category": "ios-device", "outcome": "unverified"}, {"category": "google-registration", "outcome": "unverified"}, {"category": "release-artifact", "outcome": "unverified"}, {"category": "integration-review", "outcome": "unverified"}]
}
```

## Expected and actual results

All 46 selected tests passed. They cover the new opening animation, first-use tour, Skip and durable acknowledgment, relaunch to Google login, restored-session bypass, required profile routing, fail-closed lookup, and existing Home, create-tab, settlement, privacy and recovery flows. The scoped analyzer reported no issues. The original port had an extra close in its new layout wrapper and changed line endings in three files. Both issues were corrected before independent acceptance. The Flutter package lock resolves with no package version changes.

## Evidence

[Task record](../progress/tasks/QA-051.md). The working-copy Android artifact and broader host suite are separate from this main-based port. The changes here use the same first-launch contract, with the startup frame adapted to the layout primitives already present on main.

## Limits and next action

Review and reconcile the branch with pending app changes. Build a clean signed candidate, verify the actual upgrade and complete Google and iOS device acceptance before publishing. The physical Lenovo debugging transport was unavailable during this check. Current public download remains `v1.0.4+24`.
