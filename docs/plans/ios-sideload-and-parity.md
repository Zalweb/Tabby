# iOS parity and unsigned IPA implementation plan

User asks Android/iOS feature comparison before building IPA, then chooses unsigned AltStore/Sideloadly. [QA-034](../progress/tasks/QA-034.md).

## Design

Use the same accepted shared Flutter source/assets as Android, with narrow iOS adapters. Add receiving QR save through Files export and share through the native activity sheet, preserving existing authorization/QR validation/session guards and truthful cancellation. Add FlutterDeepLinkingEnabled=false so app_links retains OAuth callbacks. Keep original Google-only flow and browser fallback. Local notifications and keychain-backed encrypted storage are supported in source but need actual iPhone acceptance. Android FCM remote push and damaged-storage archival/reset have no iOS equivalent; disclose those gaps rather than claim full parity or introduce unconfigured APNs entitlements into a sideload build.

Windows cannot run Xcode. Build on macOS CI using a fixed reviewed candidate, Flutter3.47.8 and unchanged dependency lock. Package unsigned Runner.app as Payload/Runner.app; record source/IPA digest, bundle/version, required assets, configuration presence and absence of signing/private material. This is not a TestFlight/App Store release. Preserve existing Android code/device reservations. Existing remote repository is public and older; no bulk-push of the dirty workspace.

## Steps

- [ ] Record parity matrix and claim/read set; inspect native adapters/build configuration and available macOS CI.
- [ ] Test iOS QR platform/session/error behavior; implement native Files/share adapter and OAuth callback ownership.
- [ ] Prepare deterministic unsigned workflow/scripts with client-only config, source manifest, artifact inspection and useful build evidence.
- [ ] Freeze latest accepted Android source plus reviewed iOS overlay; run relevant/full host tests and analysis, preserve root changes.
- [ ] Resolve required source-upload authorization with concrete candidate, execute macOS CI, retrieve/inspect IPA; never substitute an old remote-source build.
- [ ] Deliver artifact with parity limits and signing instructions; update task/evidence/design/memory checks.
