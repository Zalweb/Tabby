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

The Mac workflow verifies a frozen source manifest and public client configuration hashes, runs host and actual iOS simulator checks, then builds a release archive without codesigning. `scripts/ios-package.py` checks bundle/version/arm64/callback schemes, artwork hashes and absence of private signing material, and preserves executable flags in `Payload/Runner.app`. The generated IPA is **unsigned** and must be signed by AltStore/Sideloadly using the user's own Apple account. No Apple password/certificate is requested by this repository workflow. This does not publish to TestFlight/App Store.

Keep the same signer/bundle ID when upgrading so iOS can retain sandbox and Keychain access. A sideloader may change the bundle ID; native Google client registration can then differ. The existing browser OAuth fallback and callback scheme remain. Actual Google/wallet/notification/Face ID journeys should be tested on the target iPhone after signing.

`TABBY_IOS_BUILD_CONFIG` holds exactly four public client identifiers (Supabase URL/anon-or-publishable key, iOS Google client, Web Google client). It must match the reviewed Android/backend hashes and is written only to the runner's temporary directory, never an artifact or `.env` asset. Server/service-role credentials are rejected. No paid Apple signing or new backend deployment is implied.
