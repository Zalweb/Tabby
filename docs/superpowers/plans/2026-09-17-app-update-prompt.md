# Implementation Plan: Automatic App Update Prompt

## Scope

Add a release-aware update check to the Flutter app using the existing GitHub Releases pipeline. Preserve the current startup, authentication, offline, and navigation behavior.

## Work sequence

1. Add red tests for version ordering, GitHub release parsing, service failures, and the update dialog.
2. Add HTTP, package metadata, and external URL dependencies.
3. Implement the version model and GitHub release update service with defensive parsing and injected test boundaries.
4. Wrap the router content with a one-shot startup update prompt enabled for release builds.
5. Run focused tests, then the full analyzer/test suite, diff checks, and an APK build.
6. Review the final diff and document Android/iOS installation limitations.

## Acceptance criteria

- A newer release tag produces one update dialog after startup.
- The same or older release produces no dialog.
- Offline, non-200, malformed, and timeout responses never block app startup.
- Android opens the APK download when available; iOS opens the release page.
- Existing tests and auth/offline startup behavior remain intact.
