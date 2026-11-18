# iOS sideload build and Android parity

User selected an unsigned IPA for AltStore/Sideloadly. Use the latest accepted Android shared source, not the older remote main branch. [QA-034](../progress/tasks/QA-034.md) records actual build/testing evidence; source support alone is not an iPhone pass.

The pinned Flutter3.47.8 engine requires iOS15 or later. Podfile and Xcode deployment settings match that minimum; the earlier iOS13 project defaults cannot build this SDK.

| Capability | Android | iOS candidate |
|---|---|---|
| Google-only entry, intro, Home, tabs/groups, debt entry, payments/receipts, profile | Accepted shared Flutter source | Same source; native Google/device journey needs iPhone verification |
| Mascot art, articulated frames, warm themes, reduced motion | Accepted | Same source/assets; native decoding checked by CI smoke when run |
| Accounts, debt history and Realtime sync | Recorded Android backend/client config | Identical client backend config; actual cross-device Realtime remains unverified |
| Encrypted offline cache and secure key storage | Native SQLite3mc/Keystore | Same encrypted database path with iOS Keychain; real CI simulator smoke required |
| Biometrics/media picking | Android plugins | iOS plugins/Face ID/camera/Photos permissions configured; physical journey unverified |
| Local scheduled notifications | Implemented and Android device evidence | Darwin plugin/notification delegate configured; iPhone delivery unverified |
| Receiving QR save/share | Native save/share | Files export and iPad-safe native share adapter added; manual Files/wallet journey unverified |
| Remote closed-app/background reminders | Android FCM native adapter | Not implemented; no APNs entitlement/provider setup in this sideload candidate |
| Damaged-storage preserve/reset | Android-only native recovery | Retry/re-auth paths remain; no equivalent archive/reset adapter |
| App icon | Approved green Tabby launcher | Same approved launcher, not regenerated from a historical asset |

## Build and installation

The main Mac workflow verifies a clean tracked checkout at the exact GitHub commit, creates a temporary manifest from its tracked inputs, checks public client configuration hashes, runs host and actual or input-matched iOS simulator checks, then builds a release archive without codesigning. The private IPA artifact includes its commit-bound source manifest and packaging report; the paired release publisher rechecks the IPA bytes, commit, bundle ID, shared version, arm64 architecture, unsigned status and simulator evidence. The frozen `ios/build-source-manifest.json` verifier remains available for historical/frozen candidates, but current main builds do not need per-commit hash edits. Native simulator proof can be reused only when an earlier successful simulator step is verified and every app/native input hash matches; changed inputs run fresh simulator checks.

Android and main iOS use the same `pubspec.yaml` version name and build number. The former `1.0.4+5` setting is superseded by `1.0.4+25`, advancing beyond the published `1.0.4+24`; bump that one shared build number before a later public release.

The generated IPA is **unsigned** and must be signed by AltStore/Sideloadly using the user's own Apple account. No Apple password/certificate is requested by this repository workflow. This does not publish to TestFlight/App Store.

The resolved CocoaPods lockfile `ios/Podfile.lock` is committed, and the workflow fails `pod install` if it would rewrite that lock once it is tracked. Pod versions therefore stay pinned to the reviewed build instead of being re-resolved silently; update the lock deliberately when the plugin set changes.

Keep the same signer/bundle ID when upgrading so iOS can retain sandbox and Keychain access. A sideloader may change the bundle ID; native Google client registration can then differ. The existing browser OAuth fallback and callback scheme remain. Actual Google/wallet/notification/Face ID journeys should be tested on the target iPhone after signing.

`TABBY_IOS_BUILD_CONFIG` holds exactly four public client identifiers (Supabase URL/anon-or-publishable key, iOS Google client, Web Google client). It must match the reviewed Android/backend hashes and is written only to the runner's temporary directory, never an artifact or `.env` asset. Server/service-role credentials are rejected. No paid Apple signing or new backend deployment is implied.
