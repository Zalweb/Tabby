# Full-screen forms and edge-to-edge compact sheets

2026-11-17T13:13:31.045Z. User approved the proposed full-screen pages for Add/edit forms and compact sheets for quick choices, explicitly requiring sheets to cover the entire horizontal width. This approved design uses existing Flutter/Tabby warm colors, no new assets or dependencies.

## Design and interfaces

Use showTabbyFormPage<T>(context, builder) for Add Tab, payment entry, profile editing, receiving-method editing and group creation. It pushes a root MaterialPageRoute with an opaque full-viewport Scaffold, SafeArea and the existing scoped feedback host. Preserve original form widgets, their state, draft/back/session guards and operation IDs. A TabbyFormPage inherited marker lets these widgets remove sheet handles/rounded edges and provide a leading Back control. Add retains step-aware back; other forms use maybePop so PopScope remains authoritative. The route hosts all form content and keeps existing keyboard insets applied once. A full page must never paint the nav/FAB behind a partial form surface.

Quick choices (Appearance, receipt source, avatar, receiving-method selection, security/notification preferences, information) retain compact height. The common sheet wrapper sets the route width to the viewport instead of Material3's560px tablet cap and stretches its child across that width. Keep top corners, comfortable internal padding and bottom safe area. Visible feedback remains local and dismissible; session-bound callbacks cannot leak into another account.

## Implementation plan

- [x] Claim QA-030/read set/file reservations and preserve prior dirty work; no central model/provider/router/dependency changes.
- [x] Add geometry regressions for compact phone/tablet full width and full-form viewport coverage/back/message visibility; run red.
- [x] Extend shared presentation helpers and migrate only the listed long-form entry points; keep existing data callbacks. Adapt their headers/material geometry and Add scrolling.
- [x] Run focused existing form/draft/payment/feedback flows, full suite and analysis; inspect synthetic full-page/edge-sheet light/dark previews. Verify keyboard/200% text and nested choice returning to form.
- [x] Run isolated native entry suite, build a stable same-key normal17 (or later after recheck), verify certificate/source/installed bytes, preserve main/.usbtest sessions and remove only .entrytest.
- [x] Update design/reusable skill/task/evidence, refresh/validate project memory and base coverage, report actual remaining platform/review limits.

## Review focus

Back from Details returns to people before dirty-exit prompt; nested image/method choices must return to the form; field errors stay visible above keyboard; no duplicate bottom inset or inaccessible primary action at200%; compact child widths fill tablet while internal content can stay readable. Tests pin these outcomes instead of merely finding text. Independent review remains a separate gate.

2026-11-17T13:31:33.011Z - Current-source regression extension: opaque forms exposed a legacy empty-contact prefill bug previously hidden by a background text assertion. Select existing tab-only contact via its actual ID/name, retain same tab on submit, and generate a fresh contact ID only after explicit removal/replacement. No registered user is reclassified by this branch. Test actual10000-centavo append/same tab ID plus both replacement paths.

2026-11-17T13:38:38.754Z - Terminal normal18 supersedes planned17, which QA-014 used for prior accepted presentation. Execution checks pass; independent review remains open.
