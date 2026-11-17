# QA-028 — Minimal daily-debt Home and appearance choices

```json verification-metadata
{
  "id": "VER-QA-028-DAILY-HOME",
  "task_ids": [
    "QA-028"
  ],
  "timestamp": "2026-11-17T09:40:07.033Z",
  "tested_commit": "1f8b0bb7deaa05c3602a1d41c71f194818738fba",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; Lenovo TB321FU API36 ARM64 4KB; isolated .entrytest5 cases; signed normal1.0.4+15",
  "commands": [
    "dart analyze --fatal-infos lib test integration_test",
    "flutter test --no-pub --concurrency=2 --timeout=2m",
    "focused Home/appearance/actions79;8 summary and8 large-text cases",
    "two production-widget preview fixtures/24 outputs",
    "node --test scripts/usb-test.test.cjs",
    "node scripts/usb-test.cjs --suite entry",
    "skill-creator quick_validate for repository and installed Tabby design skill",
    "signed ARM64 release15, source-stability guard and expected certificate/package/ZIP16KB/ELF validation",
    "guarded same-key adb install -r; exact installed APK digest; launch/process check"
  ],
  "checks": [
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "visual-consistency",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "skill-validation",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "project-memory",
      "outcome": "passed"
    },
    {
      "category": "documentation-coverage",
      "outcome": "failed"
    }
  ]
}
```

## Expected and actual results

Home follows the user's selected reference with one warm mascot-led net-position card, one personal tab-clearance summary, a period selector, confirmed Received/Paid totals, upcoming reminders and recent activity. The functional Add dock opens the actual creation wizard alongside Home/Tabs/Profile. No nonfunctional Stats destination or promotional panel. Summary taps open tabs; notifications/reminders/activity handlers retain real behavior. Native text/gradient/cards reuse the existing transparent notebook mascot. When both obligations exist, both directions remain visible beside net; balanced overall does not imply all debts cleared.

The read-only summary counts only confirmed payment entries with explicit parties and deduplicated IDs. Date windows use recorded submission date because LedgerEntry has no confirmation timestamp; UI discloses recorded dates and excludes unattributed legacy entries with a notice. Expense/activity amounts never infer money received. Tab clearance means no current-user payable/receivable or unresolved legacy-group balance; other group members may still owe one another. Group offset/legacy/unknown-party/payment-status/date-boundary cases are explicitly tested.

Secondary cleanup removes duplicated detail header totals/mascot/progress and leaves one actionable party/balance summary plus ledger history. Profile removes static language/currency preference rows and repeated provider advertising while retaining receiving/security/friend/group/notification/appearance/sync/privacy/support/version/logout features. Existing form/session/draft/financial contracts remain. Rounded padded Appearance choices show a selected outline/radio and preserve acknowledged save/busy/failure states. Profile Edit stacks below identity at narrow/200% text widths.

Final819/819 full Flutter tests pass; analysis clean. Focused79 pass;8 pure summary and8 light/dark phone/landscape/tablet200% cases pass. Runner10 guards and both skill validations pass. Two preview fixtures produce24 synthetic light/dark/screens/overlays/tablet/full-dock states; representative Home/Appearance/Profile/detail renders inspected. Arial substitutes are fixture-only; no owner financial screenshot. Physical native suite5/5 passes, including major page/Appearance surfaces and actual dock-to-creation wizard. The test uses a distinct .entrytest package, synthetic actors/ledger and real device plugins; it does not establish real-account payment/provider acceptance.

Signed normal1.0.4+15 SHA256 1985498fb5508f516c8ce6bb30108cec983e75737e26256778bf3a277b25e15a, certificate 4867d92f6e3d814223134049eeb7b610751131c878844eeb39037ec74885e85a, nondebuggable package and ZIP16KB/native ELF checks pass. Build source-stability guard passed with no changed source files during packaging. Same-key in-place14→15 update preserves firstInstallTime/data/session; pulled installed APK matches exactly, launch Status: ok and process running. Only .entrytest removed; QA-027's authenticated .usbtest preserved. Existing six public Firebase/Azure client fields retained; no fixture login/service credentials compiled. This is a private dirty-tree tablet update, not public release.

Earlier failures are retained in [sanitized results](QA-028-results.json): obsolete duplicate-card/static-row assertions, an unclosed new root creation sheet in a test,98px Profile large-text identity overflow, hidden Ink selection and unread-icon regression. Final integrated/native/visual checks above supersede those observations.

## Evidence

[Source/results](QA-028-results.json), [exact candidate source hashes](QA-028-source-manifest.json), [task](../progress/tasks/QA-028.md), [selected design/plan](../plans/minimal-daily-debts-home.md), [design authority](../project/DESIGN.md), [updated reusable skill](../../.agents/skills/tabby-design/SKILL.md) and [native case contract](../../integration_test/android_google_entry_cases.json). Raw local logs, APKs/configs and fixture previews remain ignored. No real account financial data or credentials in evidence.

## Limits and next action

Independent integration review, iOS runtime, actual screen-reader acceptance and exact-candidate16KB runtime remain unverified; alignment is not runtime acceptance. Current host suite includes QA-027 notification/header-order repair, while real notification-tap acceptance is owned by that task and not inferred here. Existing build warnings persist. Preserve concurrent source/history and use a subsequent normal version above15. Task stays implemented until required review/integration gates pass.


2026-11-17T09:40:51.264Z — Final handoff checks: memory refresh/plain pass; whitespace passes. Base coverage fails only with24 pre-existing using-superpowers/skills-lock/supplied reference inputs lacking task ownership; no QA-028 implementation file uncovered. Candidate source still matches all201 hashes. Repository/installed design skills validate and match. Current dirty tree/prior changes retained; normal15 launched, owner data/session and .usbtest preserved. UI build reservation released; next normal version must exceed15.
