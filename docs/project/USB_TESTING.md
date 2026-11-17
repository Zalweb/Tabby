# Tablet test automation

## Google-only welcome and introduction — 2026-11-17

`node scripts/usb-test.cjs --suite entry` builds and installs only the isolated .entrytest package (TABBY_USB_TEST plus TABBY_ENTRY_TEST), rechecks hardware identity, and requires all five cases in [the case contract](../../integration_test/android_google_entry_cases.json). It renders the real Google-only welcome art, exercises intro Back/Next/Skip with real encrypted account-specific acknowledgment, checks profile-lookup failure/retry, and renders Home/tabs/details/connections/Profile/privacy plus rounded Appearance choices in light and dark mode, and verifies the real daily-debt dock Add action opens the creation wizard. It uses synthetic actor IDs and injected profile results, never a real Google login or owner financial history. Distinct application ID and auth scheme keep it separate from FCM's .usbtest fixture. Serialize root Flutter builds; the main installed package/data/session remain untouched.

## Physical local notification acceptance — 2026-11-14T03:16:51.639+08:00

```powershell
node scripts/usb-test.cjs --suite notifications --transport wifi --device <advertised-private-IP:TLS-port>
```

This API33+ suite runs3 actual local native delivery/account/preference cases, then1 denied-permission case. The runner revokes POST_NOTIFICATIONS only for the isolated test package and restores it in finally. Active notifications are queried inside that application, never across other apps. The scheduled case waits up to150seconds for actual posting and fails if it never appears; pending requests do not count as delivery. No exact-alarm/global settings change is made. [Physical results](../verification/VER-QA-013-ANDROID-NOTIFICATIONS.md) establish foreground/awake delivery and revoked-state suppression only. Nine runner checks pass.

## Current Android-only session suite — 2026-11-14T03:06:06+08:00

The current user requests Android testing only for now. [Fresh physical smoke/matrix](../verification/VER-QA-009-ANDROID-DEVICE.md) and [22 receiving/15 auth session fixtures](../verification/VER-QA-012-ANDROID-SESSIONS.md) pass on the known API36/4KB tablet. Prior device/backend observations below remain dated evidence, not current blanket acceptance. iOS runtime is deferred.

```powershell
node scripts/usb-test.cjs --suite sessions --transport wifi --device <advertised-private-IP:TLS-port>
```

`sessions` uses device-loopback synthetic HTTP/PNG and injected account/profile/clipboard ports. It does not use the ignored live config or real accounts. All suites now require clean drive success without late runtime/framework errors; sessions additionally requires all22/15 named scenarios from the checked-in case contract. Eight runner safety tests pass. This prevents the observed integration lifecycle-only false success. Explicit user-assisted manual pairing resolved the recent transport issue; no pairing code is stored. The runner itself never pairs.

## Current transport decision

Superseding user instruction on 2026-11-13: use Wi-Fi debugging after repeated USB transport failures. USB stays the runner default. Explicit Wi-Fi mode requires an already paired Android TLS service on a private IPv4 address, verifies its mDNS advertisement and records/rechecks the tablet hardware serial before installing. It never enables legacy `adb tcpip`, scans address ranges or pairs automatically. The historical `usb-test` filenames, `.usbtest` package and `TABBY_USB_TEST` define also serve this isolated Wi-Fi test build.

```powershell
adb mdns services
adb connect <advertised-private-IP:TLS-port>
node scripts/usb-test.cjs --suite live --transport wifi --device <advertised-private-IP:TLS-port> --live-config .env.usb-live.json
node scripts/usb-test.cjs --suite smoke --transport wifi --device <advertised-private-IP:TLS-port>
node scripts/usb-test.cjs --suite matrix --transport wifi --device <advertised-private-IP:TLS-port>
```

The current tablet paired successfully and passed Wi-Fi preflight, live Azure Auth/API/Realtime, native smoke and the scripted device matrix. See [physical evidence](../verification/VER-QA-002-WIFI-TABLET.md). Port/address can change after a reconnect; use its current advertised TLS endpoint. Five transport/package/configuration safety regressions pass. Existing USB-only paragraphs below describe the original implementation; this dated decision supersedes their restriction on explicitly selected Wi-Fi transport.

Owner: [QA-002](../progress/tasks/QA-002.md). Source implementation is distinct from device or live-backend evidence.

## Run

Connect one physical Android device by USB, unlock it and accept the USB debugging prompt. Wireless debugging is never used. Node, Git, the existing Flutter SDK, and Android SDK are required. SDK locations default to the untracked `android/local.properties`; `--flutter-root` and `--android-sdk` can override them. Run from the repository root:

```powershell
node scripts/usb-test.cjs --suite preflight
node scripts/usb-test.cjs --suite smoke
node scripts/usb-test.cjs --suite smoke --repeat 3
node scripts/usb-test.cjs --suite matrix
node --test scripts/usb-test.test.cjs
```

The runner uses `adb -d` to select USB transport. It validates a physical device, pins Flutter to its USB serial and rechecks that serial before each installation. It never runs `connect`, `tcpip`, pairing, package-data clearing or uninstall. Flutter's device bridge may forward the local Dart VM service over USB; this does not enable wireless ADB.

The debug-only `TABBY_USB_TEST=true` build installs **Tabby USB Test**, package `com.zalweb.tabby.usbtest`, with separate private storage and OAuth scheme. The runner checks the actual APK package before installing. It preserves `com.zalweb.tabby`. Release/profile test builds are rejected by Gradle. Notification permission is granted only for the test package. No camera prompt, settings change, reboot or other-app interaction is needed by the smoke suite.

`smoke` builds and executes two APKs. The seed persists a synthetic PIN and encrypted financial draft. The runner stops that process before the smoke APK verifies native persistence, owner isolation, correct/incorrect PIN verification, notification preference scheduling/cancellation and tablet rendering/touch input. Each repetition reseeds its synthetic state. These are physical platform tests with fixtures, not a live financial journey or a full application acceptance suite.

`matrix` automates the existing SEC-001/003 and HOME-001..004 fixtures with a seed and real process stop between APKs. Dashboard data is synthetic. Its HOME-004 cases **schedule probes only**; successful test execution does not establish background/force-stop delivery. Native biometric interaction, low-memory profiling, permission denial, reboot, picker process death, OEM battery restrictions, real FCM delivery, wallet deep links, 16 KB runtime and signed upgrade tests remain separate acceptance work.

## Live backend

Once the Azure restore is ready, create an ignored `.env.usb-live.json` using this shape. Supply a dedicated synthetic fixture account provisioned on the restored backend; never use a real person's login.

```json
{
  "SUPABASE_URL": "https://CHANGE_ME",
  "SUPABASE_ANON_KEY": "CHANGE_ME",
  "TABBY_LIVE_TEST": "true",
  "TABBY_TEST_EMAIL": "CHANGE_ME",
  "TABBY_TEST_PASSWORD": "CHANGE_ME"
}
```

```powershell
node scripts/usb-test.cjs --suite live --live-config .env.usb-live.json
```

The configuration must be Git-ignored, use HTTPS, explicitly opt in, and use an anon/publishable key. The current hosted production endpoint and service-role keys are rejected. The fixture password is compiled into the private debug APK: do not upload the APK, build directory or configuration. Rotate the fixture password after testing. Local logs redact configured credentials and JWTs; inspect logs before sharing.

The live suite signs in through real Auth, verifies the session with Auth, reads only its own profile ID, checks that the review RPC exists and rejects a nonparty, and asserts app roles cannot directly read protected review tables or server rollout flags. It verifies a real Realtime UPDATE on the tagged synthetic account, waiting for explicit replication readiness and restoring its display name, then signs out only the fixture session. This is bounded Auth/API connectivity and denial acceptance, not payment concurrency, Storage, Realtime, scheduler, financial journey or migration integrity acceptance. M2 stays disabled.

## Reports and automation

Every runner invocation writes `.dart_tool/usb-tests/<UTC-run-id>/report.json` and per-command logs. Reports contain the tested commit, dirty-tree flag, physical device/API/page size, suite, step duration and pass/fail. Nonzero build/device/test results fail the run. Missing live setup is not a passing live test. Raw device-wide logcat, notifications, screenshots and user databases are not collected.

Use the runner command as the test job in a **local trusted** scheduler or pipeline on this USB-connected computer. `--repeat` provides bounded repeated runs. Hosted CI cannot access a locally attached tablet; do not register this personal device host as a runner for untrusted pull requests. Reconnect/authorize USB after any OS reset. Test reports remain local and ignored; commit only sanitized summaries through the [verification protocol](../verification/README.md).

## 2026-11-14T14:20:41.074+08:00 — Explicit 16KB emulator and lifecycle runners

Use `node scripts/android-emulator-test.cjs --device emulator-5580 --suite all` for native storage/session/local-notification cases on an already booted official API36 google_apis_ps16k x86_64 image. It refuses physical devices and4KB runtimes. The four storage cases preserve only synthetic .usbtest state across process/reinstall and verify encryption/missing-key/rollback. Use `node scripts/android-cold-launch-test.cjs --device emulator-5580 --mode closed` or `--mode reboot` for actual drawer-to-cold-app payload/draft/PIN verification. Reboot is emulator-only; never point this at a personal tablet. Unique fresh UI dumps and exact synthetic title bounds are required. The personal-tablet Wi-Fi hardware checks remain mandatory for scripts/usb-test.cjs. Builds regenerate plugin registration when switching release/debug. See [16KB](../verification/VER-QA-014-16KB.md), [lifecycle](../verification/VER-QA-016-LIFECYCLE.md) and [signed staging limits](../verification/VER-QA-015-SIGNING.md).

## 2026-11-14T14:33:57.367+08:00 — Private release-signed storage rehearsal

The explicit emulator-only `scripts/android-signed-storage-test.cjs` requires `--device emulator-<port>`, `--baseline-apk`, `--public-config` and `--expected-cert`. It refuses physical/implicit targets, matches the emulator-installed APK against the supplied exact signed baseline, prepares real-main restoration before replacement, then installs seed/verify/higher restoration versions with one new production key. Public config accepts only anon/client identifiers, never fixture passwords or service-role credentials. This temporarily uses com.zalweb.tabby only on the owned16KB emulator, never the personal tablet. All runtime validations work in release AOT. [Evidence/limits](../verification/VER-QA-019-SIGNED-STORAGE.md).
