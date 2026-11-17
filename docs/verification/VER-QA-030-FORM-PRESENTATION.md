# QA-030 - Full-screen forms and full-width compact sheets

```json verification-metadata
{
  "id": "VER-QA-030-FORM-PRESENTATION",
  "task_ids": [
    "QA-030"
  ],
  "timestamp": "2026-11-17T13:38:38.754Z",
  "tested_commit": "b4f5671486e37eab468567bedb90d1f428b54302",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; Lenovo TB321FU API36 ARM64 4KB; isolated .entrytest5; signed universal1.0.4+18 on ARM64 tablet and native x86_64/16KB emulator",
  "commands": [
    "flutter test --no-pub --concurrency=2 --timeout=2m",
    "dart analyze --fatal-infos lib test integration_test",
    "11 presentation geometry/identity cases and7 feedback cases",
    "node scripts/usb-test.cjs --suite entry",
    "node --test scripts/usb-test.test.cjs",
    "six synthetic full-page/compact sheet previews",
    "skill-creator quick_validate repository and installed design skill"
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
      "category": "presentation-geometry",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "skill-validation",
      "outcome": "passed"
    },
    {
      "category": "release-artifact",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
    },
    {
      "category": "16kb-device",
      "outcome": "passed"
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

Approved full-screen presentation uses showTabbyFormPage for Add Tab, payment entry, Profile editing, receiving-method editing (including staged registration) and both group-creation entry points. Root MaterialPageRoute is opaque and covers the entire viewport; SafeArea/pinned guarded Back/header and scrolling form fields replace sheet handles/rounded edges. Add retains step-back and draft prompts; no new provider/router/model/native dependency. Existing account/draft/operation and payment confirmation rules remain.

Quick sheets retain compact height and rounded top corners while actual surface/content spans right to left, including tablets and resize. Removed the old560px shared theme cap and enforce dynamic route width rather than a fixed opening width. Scoped messages continue to target current forms/sheets, reject old-session callbacks and return success to active parent/page.

Full837/837 and full analysis pass.11 new presentation cases cover full opaque Add bounds, nested receipt-source return, two viewport widths plus resize, actual Profile/Appearance surfaces in both themes, receiving/payment200% keyboard reachability with pinned Back, and contact replacement identity.7 existing feedback cases now target the active full-screen host and test true logical keyboard insets. Final physical5/5 entry cases pass and measure full-screen Add/no BottomSheet/visible validation and actual edge-to-edge Appearance in both themes. Runner10 guard tests pass. Six synthetic production-widget previews (Add/Profile phone and Appearance tablet, light/dark) render and representative outputs were inspected; substitute fonts are fixture-only and no owner financial screen was captured.

Opaque presentation exposed an existing empty-contact prefill defect previously hidden by background name text. Red regression proves actual form lacked selection; seeding tab-only counterpart ID/name now makes real submission retain one tab, same tab ID/contact ID, and one10000-centavo appended expense. Explicit removal/replacement creates a fresh ID, checked via retained draft. Registered users are not reclassified. No financial history/model/backend changes.

Earlier failures: test finders assumed Close/BottomSheet and background duplicate titles; updated interactions use real Back/full-screen context while retaining business assertions. Fixed width cached at open failed rotation. Pinned Add header plus notice/large text overflowed73px; optional selected count is omitted above130% text scale while actual selections remain. Initial keyboard assertions mixed physical/logical pixels and now scale through DPR. First full828/835 failed five old modal assumptions plus two keyboard assertions; final837 above supersedes it. Task-record heading validation failed once and was corrected to the required template.

## Evidence

[Task](../progress/tasks/QA-030.md), [approved design/plan](../plans/fullscreen-forms-and-edge-sheets.md), [geometry/identity tests](../../test/features/presentation_routes_test.dart), [native case contract](../../integration_test/android_google_entry_cases.json), [design skill](../../.agents/skills/tabby-design/SKILL.md). Native final report is local .dart_tool/usb-tests/2026-11-17T13-30-45-912Z/report.json; public sanitized results/source manifest attach after candidate delivery. Raw local logs/APKs/configs/previews remain ignored.

## Limits and next action

Normal17 from QA-014 is a deliberately frozen prior presentation build and cannot establish delivery of these forms. Its terminal release was reviewed; package stable current-source universal18, verify same-key17-to18 installed bytes/data-preserving update and exact18 native16KB emulator startup. Those checks are pending at record creation. Independent integration review, iOS runtime and real screen-reader acceptance remain unverified; no public release/backend migration or money movement.

2026-11-17T13:38:38.754Z - Terminal superseding delivery: stable current-source universal1.0.4+18 built exit0/no drift across203 app source files, expected production certificate, nondebuggable package and ZIP16KB/ELF checks pass for ARM64/x86_64. Exact installed SHA256 e23b67b28ffe09e5ad84cf2fce1868dddaf5b43692191d93c27723fcffcd26b1 matches pulled tablet bytes;17-to18 in-place retains original firstInstallTime/data/login, launches and remains running. Only .entrytest removed; .usbtest preserved. Same exact signed APK installed17-to18 on owned official API36/16KB emulator, selected native x86_64, process/resumed/no fatal/loader error and actual signed-out Google welcome observed. This supersedes creation-time pending delivery/runtime statements above; startup is not a full signed-in16KB flow.

[Sanitized results](QA-030-results.json), [exact candidate source hashes](QA-030-source-manifest.json), [UI/test/skill hashes](QA-030-ui-source-manifest.json). Original target17 was superseded after QA-014 installed its accepted prior-presentation universal17; those forms were not adopted. Generated dev-only plugin registrant was safely regenerated after the native test, without modifying tracked source. Existing Kotlin/plugin/font build warnings remain. Final plain/refresh memory pass; base coverage fails only on24 pre-existing unclaimed skill/lock/reference inputs, with no QA-030 file uncovered. Required independent review remains open; no complete/public release claim.
