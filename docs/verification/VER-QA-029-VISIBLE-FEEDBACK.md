# QA-029 — Visible feedback and lower-right Add

```json verification-metadata
{
  "id": "VER-QA-029-VISIBLE-FEEDBACK",
  "task_ids": [
    "QA-029"
  ],
  "timestamp": "2026-11-17T10:27:13.541Z",
  "tested_commit": "d0d07126da9b05d29dc8860508e44cd752cbda5a",
  "dirty_tree": true,
  "environment": "Windows / Flutter3.47.8 Dart3.13.7; Lenovo TB321FU API36 ARM64 4KB, isolated .entrytest; final5-case drive and signed normal1.0.4+16 exact installed bytes",
  "commands": [
    "flutter test test/features/sheet_feedback_test.dart",
    "flutter test --no-pub --concurrency=2 --timeout=2m",
    "dart analyze --fatal-infos lib test integration_test",
    "native entry suite5 cases; runner10 guards",
    "production-widget Home/Add light/dark/200% preview fixture",
    "skill-creator quick_validate repository/installed design skill"
  ],
  "checks": [
    {
      "category": "feedback-visibility",
      "outcome": "passed"
    },
    {
      "category": "analysis",
      "outcome": "passed"
    },
    {
      "category": "regression",
      "outcome": "passed"
    },
    {
      "category": "android-device",
      "outcome": "passed"
    },
    {
      "category": "integration-review",
      "outcome": "unverified"
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

The Add validation red test found text on the page messenger but no matching text inside the bottom sheet. The shared showTabbyBottomSheet wrapper now installs a local feedback host; TabbyFeedback routes messages to the visible sheet in the same messenger or to its page. Nested sheets own their notices. Popping a saved form re-resolves its active parent/page, rather than dropping success. Captured callbacks from an older account session cannot show feedback. Realtime notification presentation uses the current sheet host; delivery/authorization/readiness are separate QA-027 work. Existing receiving/payment inline errors remain inline.

A further red case proved that an inactive StatefulShell branch can retain a local-current route. Current-route plus enabled TickerMode excludes it; seven focused behavioral cases pass. The Add wizard also overflowed in progress labels/person action at200% text, with insufficient vertical space when the keyboard and notice were present. Whole-form scrolling, flexible progress labels and a stacked person action fix those overflows while preserving draft/back/retry behavior.

Home/My Tabs expose the actual Add handler as a lower-right floating action. Three navigation items have equal horizontal spacing, with My Tabs centered. Add is absent on Profile/detail; extra bottom scroll space keeps final list actions reachable. No financial logic, authenticated identity, confirmed history or backend contracts changed.

Current analysis passes. Earlier full825 passes before the additional inactive-branch regression; final826 suite pending at record creation. Two real five-case entry drives pass before that final visibility predicate, including tapping the FAB and hit-testing the blank Add Person error inside BottomSheet, then dismissing it. Three synthetic production-widget previews cover Home dock, light Add error and dark200% Add error. Substituted preview fonts are fixture-only, and no real owner financial screenshot was captured.

Initial focused46/48 exposed two post-pop success losses; corrected tests pass18/18 after realistic facade cleanup. First full822/825 missed three buttons moved into scrollable content; ensureVisible interactions pass19/19 with the fixture. First normal16 packaging Flutter exit0 was rejected because three separately-owned QA-027 native sources changed during the build; no candidate was installed. QA-027 now owns shared Android output/device reservation for its cold-tap fix.

## Evidence

[Task](../progress/tasks/QA-029.md), [plan](../plans/ui-feedback-audit.md), [design](../project/DESIGN.md), [scoped feedback regression](../../test/features/sheet_feedback_test.dart), [native case contract](../../integration_test/android_google_entry_cases.json) and [reusable skill](../../.agents/skills/tabby-design/SKILL.md). Exact candidate/results will be attached after the shared build/device reservation is released. Skill search confirmed [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) is already installed and supports Flutter/interface reviews; no new package installation.

## Limits and next action

Final integrated/native/candidate and documentation checks pending at creation; do not infer them from an earlier drive or a rejected build. Independent integration review, iOS runtime, real screen-reader acceptance and exact-candidate16KB runtime remain unverified. Actual remote notification warm/cold tap acceptance belongs to QA-027. Preserve its .usbtest session and all dirty prior work. This is a private UI update, not public release approval.

2026-11-17T10:21:27.490Z ? Final integrated host826/826 passes, current-SDK7/7 feedback cases pass and analysis is clean. These supersede pending host statements at record creation. [Final UI/test source hashes](QA-029-ui-source-manifest.json). Native/candidate reservation still pending; no main16 install claimed.

2026-11-17T10:27:13.541Z - Terminal superseding evidence: full826/826, feedback7/7, clean full analysis, runner10 guards and final physical5/5 entry cases all pass on frozen current UI. Normal1.0.4+16 from QA-027 integration owner includes all21 UI lib hashes, with all203 current app source hashes still matching its zero-drift manifest. Expected production certificate/package/nondebuggable ZIP16KB/ELF checks pass. Exact installed SHA256 02dd7199462e1ffc1b24372aa1e95c8b76a8b893475899982220cd3c9e240f8f matches pulled bytes;15-to16 in-place update preserved original firstInstallTime/data/login. Main launch/process pass. Removed only synthetic .entrytest; authenticated .usbtest remains. No duplicate install or real financial screenshot. These results supersede all creation-time pending native/candidate statements above.

[Sanitized results](QA-029-results.json), [exact candidate hashes](QA-029-source-manifest.json) and [UI/test hashes](QA-029-ui-source-manifest.json). Shared build/device reservation released. Existing plugin/Kotlin/font warnings persist; no new failure inferred from warnings alone. Memory refresh/plain pass; base coverage fails only on24 pre-existing unclaimed skill/lock/reference inputs, with no QA-029 implementation uncovered. Required independent review remains open; task stays implemented.
