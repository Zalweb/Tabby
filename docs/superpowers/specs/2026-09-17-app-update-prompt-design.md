# Automatic App Update Prompt

## Status

Approved for implementation on 2026-09-17.

## Goal

Let Tabby notify users when a newer tagged release is available without blocking startup, login, onboarding, or offline use.

## Update source

The app reads the public latest-release metadata from the Tabby GitHub repository. The existing Android and iOS workflows already publish versioned APK and IPA assets to that release, so no Supabase schema or credential changes are needed.

The client compares the installed `pubspec` version and build number with the release tag. Invalid responses, network errors, and malformed tags are treated as no update so the app remains usable.

## User experience

1. After the first frame, a release build performs one non-blocking update check.
2. If a newer release is found, a friendly dialog shows the new version and release notes.
3. `Later` dismisses the dialog for the current launch.
4. `View update` opens the Android APK asset on Android and the release page on iOS.
5. The dialog uses Tabby’s existing warm, concise copy and does not use debt-collection language or emojis.

## Platform boundaries

Android can download the APK from the release page, but the operating system still requires the user to approve installation. iOS cannot install a sideloaded IPA silently from inside an app; the release page is opened so the user can follow the existing Sideloadly or distribution flow. Store/TestFlight URLs can replace the release URL later without changing the update-check contract.

## Client architecture

- `AppVersion` owns defensive semantic version and build-number comparison.
- `AppUpdateService` fetches and maps GitHub release metadata using an injected HTTP client and installed-version provider.
- `AppUpdatePrompt` runs the check once after startup and owns the dialog lifecycle.
- The production `main()` entry point enables the automatic check in mobile debug and release builds; direct `TabbyApp` test construction leaves it disabled unless explicitly enabled. Injected services remain available for deterministic widget tests.

## Non-goals

- Silent APK installation.
- In-app IPA installation or certificate management.
- Forced updates or blocking older app versions.
- Supabase migrations, push notifications, or background update checks.

## Verification

Test version ordering, release JSON mapping, HTTP failure handling, and dialog actions. Run `flutter analyze`, `flutter test`, `git diff --check`, and a debug APK build.
