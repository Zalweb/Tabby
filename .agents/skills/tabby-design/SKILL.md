---
name: tabby-design
description: Build or review Tabby's Flutter pages, forms, navigation and overlays using its warm cream, amber and charcoal mascot design. Use for Tabby UI changes and consistency reviews.
---

# Tabby design

Keep the experience continuous from Google-only welcome and introduction to Home, tabs, expenses, connections, payments, profile, settings and system states. Match the existing Tabby identity; do not invent a separate palette per page.

In a Tabby checkout, read `docs/project/DESIGN.md` and current decisions first. Use `lib/core/theme/tabby_colors.dart`, `tabby_palette.dart` and `tabby_theme.dart` as the implementation source. Newer explicit user direction takes precedence over this skill. Do not change authentication, ledger behavior or deployment scope merely to change UI.

## Visual roles

| Role | Light | Dark |
|---|---|---|
| Canvas | #FFFAF2 cream | #181A19 charcoal |
| Raised surface | #FFFFFF | #242625 |
| Soft input/highlight | #FFF0D8 | #33302A |
| Primary text | #292321 | #FFF8ED |
| Supporting text | #6B6058 | #C7C1B7 |
| Action fill | #FFB342 amber | #FFB342 amber |
| On amber | #292321 | #292321 |
| Links/focus | #8A4B08 | #FFC975 |

Use `TabbyPalette.of(context)` for canvas, surface, soft, text, secondaryText, link, controlBorder and semantic status colors. Fixed `TabbyColors.brandAmber` with `brandInk` is appropriate for filled actions. Never use pale amber text/icons on cream or white, white labels on amber, or fixed light surfaces in dark mode. A subtle card separator may use `border`; interactive input boundaries use the stronger `controlBorder`, and focus uses `link`.

## Composition

- Cream page headers, warm-white cards, restrained amber selection and one clear primary action. Keep forms and long pages scrollable. Use roomy spacing in multiples of4/8,16px control corners,20–24px cards and28px sheet corners; adapt existing components rather than rebuilding every page.
- Keep native text readable and concise, with strong charcoal headings and quiet supporting copy. Use the app's existing Inter typography. Preserve200% scaling, keyboard insets, reachable actions, screen-reader labels and48px touch targets.
- Prioritize the actual mascot at welcomes and meaningful empty/summary states. Existing assets: `assets/branding/tabby-welcome-v3.png`, `tabby-notebook-v3.png` and the shared blink sprite/widget. Native code supplies text, controls and motion. Avoid extra badges, decorative icon clusters and oversized illustrations beside dense financial forms.
- Use restrained functional icons with readable warm foregrounds. Preserve provider logos, user photos, receipts, QR content and white QR quiet zones. Never recolor these image pixels to match the theme.
- Light/dark modes share hierarchy and amber actions; use charcoal dark surfaces, not teal. Honor reduced motion and pause ambient mascot motion when hidden/backgrounded.

## Daily-debt hierarchy

Home uses one mascot-led net-position hero, one personal tab-clearance summary, an activity period filter, confirmed Received/Paid totals, due reminders and recent activity. Keep one working Add floating action at the lower-right on Home/My Tabs, above three evenly centered Home/My Tabs/Profile destinations; hide Add on Profile and detail pages. Reserve bottom scroll space so the final list action remains reachable; do not copy a Stats destination unless it has an actual implemented feature. Remove duplicated totals, decorative percentages and promotional panels. Secondary pages prioritize working actions; static PHP/English facts belong in About rather than separate preference rows.

Net zero can hide opposite group obligations. Show both payable/receivable totals when both exist, and count a tab clear only when the current user has neither outstanding direction nor unresolved legacy shares. Label this progress "clear for you", not all members settled. Received/Paid count only confirmed entries with explicit payer/recipient, using recorded payment dates and deduplicated IDs; neither an expense nor an activity description proves received money.

Mode choices use padded16px rounded Material/ListTile shapes with a readable selected border/radio, not flush square highlights. Ensure the selected fill paints on the nearest Material; a DecoratedBox above Ink can hide selection. Keep Profile identity and Edit action adaptive at200% text size. Preserve actual preference persistence/busy/error behavior while changing appearance.

## Financial meaning

Ordinary debt is not an error. Keep labels such as You owe, You are owed, Submitted and Awaiting confirmation. Semantic green is reserved for positive confirmation/success; readable red for errors/destructive actions. Pair status colors with text. Payments happen outside Tabby; attaching/scanning a QR or receipt never confirms payment. Do not infer new budgets, AI, chat or payment-processing features from reference artwork.

## Applying and checking changes

Check shared components and explicit page styles together: theme changes alone miss hardcoded headers, chips, icon colors, snackbars, startup/lock screens and sheets. Reuse the shared palette, buttons and native Material theme. Preserve business logic and session/draft guards.

Verify normal body text at4.5:1; controls/focus boundaries and meaningful icons at3:1. Inspect representative phone/tablet/light/dark states, small/landscape/200% layouts and actual dialogs/sheets. Keep QR contrast intact. Run relevant UI regressions and analysis; distinguish fixture previews from physical/live acceptance. Update the design/task evidence when the contract changes. This skill grants no permission to sign out users, clear data, deploy or publish.

## Visible feedback

Use showTabbyBottomSheet for app sheets and TabbyFeedback.of(context) for transient form feedback. A plain page ScaffoldMessenger can render underneath a modal. Show validation and retry messages in the active sheet, with a live region and a labeled dismiss control; keep existing field/save errors inline. Realtime banners use TabbyFeedback.current; inactive StatefulShell branches must not capture them even when their local route remains current. Require enabled TickerMode as well as current-route visibility. After a successful form closes, route feedback to its current parent/page, and discard callbacks from an older account session. Preserve draft/session guards. Do not count find.text alone as visibility: verify hit testing and paint bounds, nested routes, post-pop success, keyboard,200% text and both themes. Keep the entire Add form scrollable when vertical space is constrained; progress labels and form actions must wrap without overflow.

## Form pages and compact sheets

Use showTabbyFormPage for Add Tab, payment entry, profile/receiving-method editing and group creation. The opaque full-screen route keeps existing PopScope/account/draft and save callbacks; use TabbyFormBody with a pinned TabbyFormHeader and scrolling fields. Add keeps its step-aware Back. Remove drag handles/rounded sheet edges on full pages; leave status/navigation safe areas and apply the keyboard inset once. Keep primary actions reachable at200% text without hiding Back.

Use showTabbyBottomSheet for quick choices and concise information. Compact means content-driven height, not side gutters: both theme and wrapper fill the current viewport width, including tablet/rotation. Retain top corners, internal padding, safe areas and active-sheet feedback. Full-width route geometry must not be inferred from the BottomSheet widget alone; measure its actual surface/content and verify nested choices return to their form.

## Situation mascot animation

Use TabbyMascotWidget.art and TabbyMascotPose for art-only roles; preserve one mascot per meaningful state and avoid decorative badges around forms. Existing MascotEmotion maps to neutral/notebook/thinking/waiting/reminder/celebrating/sleeping; helpful/welcome are presentation overrides. Approved supplied originals live in assets/branding/mascot with artwork-manifest.json; keep their bytes and use normalized alpha bounds/display-bounded decode for stable sizing. QA-033 adds sibling -frames-v1.png sheets and frame-manifest.json for actual eye/tail/paw articulation in the five new situation poses. Use the measured fixed-size source windows and existing playback engine; do not tightly rescale each frame or alter originals. Thinking/waiting blink and swish; helpful/reminder add occasional paw gestures; success gestures finish once. Welcome/notebook keep their existing whole-body motion; original neutral blink remains.

Frame clips have long quiet holds, not perpetual waving. Missing/loading sheets fall back to the approved original; reduced motion uses original still art. Decode at a bounded atlas width appropriate to the displayed cell. Verify actual source-rectangle changes, fixed window size, native image loading and missing-sheet fallback; a body transform alone does not establish paw/tail/eye animation.

Pause all controllers and sprite timers when offstage, covered or backgrounded; system/app reduced motion renders untransformed still art immediately. Celebration is finite and cannot replay on parent rebuild or resume. Pending payments use waiting; celebrate financial settlement only on confirmed existing status. A created tab can use art-only celebration without claiming settled funds. Do not introduce scary debt expressions or mascot feedback on every validation field. Test real PNG decoding, asset/pose mapping, matrix motion, reduced motion, hidden/lifecycle pause and one-shot completion on host and native fixture; synthetic previews are not real account tests.
