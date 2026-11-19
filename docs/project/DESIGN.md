# Design and language

## Current app-wide design — 2026-11-17T08:16:51.570Z

The user's explicit follow-up extends the login/introduction design to **every Tabby page**. This section and [DEC-014](DECISIONS.md#dec-014--one-warm-design-across-tabby) supersede the earlier mint/emerald baseline and DEC-013's auth-only color scope. Earlier dated material below remains historical; it must not reintroduce a second theme.

### Shared palette

| Role | Light | Dark |
|---|---|---|
| Canvas | #FFFAF2 | #181A19 |
| Surface/card/sheet | #FFFFFF | #242625 |
| Soft input/highlight | #FFF0D8 | #33302A |
| Main text | #292321 | #FFF8ED |
| Supporting text | #6B6058 | #C7C1B7 |
| Muted text | #75685F | #B5ADA2 |
| Action fill | #FFB342 | #FFB342 |
| On action | #292321 | #292321 |
| Link/focus | #8A4B08 | #FFC975 |
| Card separator | #E7D8C5 | #51493E |
| Control boundary | #8E7D6D | #B5A38D |

Source of truth: lib/core/theme/tabby_colors.dart (fixed brand), tabby_palette.dart (theme roles) and tabby_theme.dart (native controls). WelcomeColors delegates to that same palette. Legacy emerald/mint/blue aliases remain compatibility names only; use the canonical warm names and semantic roles in new code. No page-specific raw brand hex values. Provider logos, avatars, receipt/image pixels and white QR quiet zones retain their actual colors.

### Composition and components

Use cream page headers and backgrounds, warm-white raised cards, charcoal headings, restrained amber actions/selected controls and readable burnt-brown links. Dark mode follows the introduction's charcoal canvas and warm ink, with the same amber fill. Amber text on cream/white and white text on amber are prohibited. State labels, input boundaries and focus indicators must stay readable; pale decorative borders are not sufficient control outlines.

Keep existing Inter typography, bold22–28px page titles,16px body/form text where practical and readable supporting copy. Use4/8px spacing steps,16px controls,20–24px cards,28px sheet corners and48px touch targets. Preserve native text scaling, keyboard/safe-area handling, scroll-reachable actions, system back and screen-reader names. Ordinary routes, search/filters, settings, creation/edit/payment forms, dialogs, menus, notifications, loading/error/empty states and startup/lock screens all consume shared warm roles. Use restrained hero gradients; routine ledger pages remain information-first rather than saturated amber screens.

Prioritize the existing transparent welcome/notebook Tabby and shared blink sprite at meaningful welcome/summary/empty states. Home carries the notebook mascot instead of the decorative receipt ring. Keep logos/native text out of generated artwork. Avoid icon clusters, unnecessary avatar choices or decorative status badges competing with financial information. Motion respects reduced-motion preferences and hidden/background lifecycle. Existing launcher artwork is unchanged by this UI migration.

### Product meaning

Preserve friendship-first calm English without emoji, PHP/integer-centavo amounts and append-only confirmed history. Use precise labels: You owe, You are owed, Submitted, Awaiting confirmation, Receipt attached, Archived. Ordinary debt does not use error red. Green may indicate actual success/confirmation; red indicates real errors/destructive actions; pair all status colors with text. Displaying/scanning QR or attaching a receipt never confirms payment or moves money. Google remains the sole normal entry; introduction/profile/session/draft behavior is unchanged.

### Maintenance and verification

Use the reusable [tabby-design skill](../../.agents/skills/tabby-design/SKILL.md), also installed in the user's Codex skills directory. [QA-026 plan](../plans/consistent-warm-ui.md) covers migration and verification. Check shared tokens **and** explicit page overrides. Verify4.5:1 body text and3:1 meaningful controls/focus/icons, light/dark phone/tablet and small/landscape/200% text, overlays and QR integrity. Fixture screenshots are not live Google/device acceptance; task evidence records actual environments and remaining gates.

## Historical design checkpoints

The following material is retained for chronology. Current app-wide design above takes precedence.


Use existing Flutter theme/color tokens as the current implementation baseline: Emerald #00D09E, Dark Teal #093030, Mint Canvas #F1FFF3 and white surfaces. Historical charcoal/amber examples are archived reference material, not a request for a redesign. Brand assets and mascot mood sheets remain under assets/branding.

Preserve warm English copy without emoji. Label financial state precisely: You owe, You are owed, Submitted, Awaiting confirmation, Receipt attached, Archived. Do not imply verified payment from an uploaded image. Standard pending debt must not use threatening copy or alarm styling.

Use semantic theme surfaces/text for light/dark appearance, respect reduced motion, keyboard insets and system back. Support 200% text, small screens and landscape. QR previews preserve quiet zones and allow full-screen/save/share for same-phone wallet import.

M1 exposes PHP and English only; remove incomplete currency/language selectors. Later additions require complete screen coverage and a recorded product decision.

## Mascot artwork — 2026-11-17T11:10:22+08:00

The supplied transparent eight-pose [blink sheet](../../assets/branding/tabby-blink-sheet.png) replaces the circular static mascot image inside the shared widget. Measured equal-size source rectangles align the paws across uneven sheet gutters. Hold open eyes for 3.2 seconds, then play a short blink; keep the existing emotion badges, messages and body motion. This artwork provides an idle blink and closed eyes for sleeping, not nine separately drawn emotional poses. Reduced motion keeps a static pose, and hidden routes/background lifecycle pause sprite playback. Sleeping uses the closed-eye frame and does not blink.

The generated [opaque launcher icon](../../assets/branding/tabby-launcher-v2.png) and [transparent adaptive foreground](../../assets/branding/tabby-launcher-foreground-v2.png) preserve Tabby's charcoal/white/orange character with emerald branding. Both launcher configurations reference these versioned assets. Generate sizes with the existing flutter_launcher_icons package; then preserve the 12dp foreground inset in android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml so ears/paws remain within adaptive masks. Android, iOS and web icon resources are generated together; iOS runtime remains unverified. Generation prompts/provenance and actual verification belong to [QA-023](../progress/tasks/QA-023.md).

## Login presentation — 2026-11-17T11:42:18+08:00

The login page uses a larger full-body blinking Tabby with a soft mint illustration backdrop and a short greeting, omitting the compact financial-status ring/badge. A bounded surface card groups Google and email sign-in, recovery and signup. At widths of at least 900 logical pixels, use side-by-side illustration/form columns with a 440-pixel form; smaller widths and large text stack the content. Keep the page scrollable for keyboard/small landscape, and wrap all action/divider text at 200% scaling. Keep semantic light/dark colors, reduced motion and existing authentication callbacks/session guards. The shared mascot's backdrop/badge options default on for existing consumers. See [QA-024](../progress/tasks/QA-024.md).

## Google-only welcome — 2026-11-17T15:35:18.301+08:00

Supersedes the preceding login presentation under the user's explicit [DEC-013](DECISIONS.md#dec-013--google-only-entry-and-post-authentication-introduction). Use a warm cream-to-amber welcome with one Google action and a large generated full-body Tabby. No email/password fields, signup/recovery links, Apple or offline actions in normal entry. Keep existing recovery deep links functional for pending legacy recovery sessions. The Google mark is the official downloaded raster asset, not an improvised glyph.

After Google, incomplete registration sees three clean, one-message screens: meet Tabby; shared expenses and bilateral tabs; external payments plus recipient confirmation. Use generated welcome/notebook characters, a small progress bar and Back/Next/Skip; no decorative icon collections or unsupported chat/AI/budget claims. Name and Philippine mobile setup follow, then optional receiving methods. Setup omits the previous decorative avatar picker, preserves a Google avatar if present, and constrains forms to460 logical pixels. Completed server profiles go home; retry unknown profile checks. Introduction acknowledgment uses encrypted account-specific storage, not the historical device-wide pre-login tutorial flag. Assets and exact prompts are in [QA-025 provenance](../assets/google-welcome-prompts.md).


2026-11-17T08:50:16.794Z — [QA-026 implemented verification](../verification/VER-QA-026-WARM-UI.md) supersedes previous rollout-pending statements: normal tablet14 now uses the app-wide warm contract. Remaining platform/review gates are explicit in evidence.


## Minimal daily-debt Home and choices — 2026-11-17T09:27:12.728Z

The user's supplied Home reference now defines the hierarchy: one warm mascot-led net-position card, one personal tab-clearance summary, period-filtered confirmed Received/Paid totals, upcoming reminders and recent activity. Omit repeated balance cards/decorative percentages/promotional blocks. Use the actual Home/Tabs/Profile routes plus a working Add action; a nonfunctional Stats destination is not part of this implementation. Existing transparent notebook Tabby and native gradient/text supply the hero without new bitmap UI.

Outstanding totals remain the existing integer-centavo obligations. Show both directions when payables and receivables coexist; zero net alone does not mean settled. Progress is explicitly clear for you and respects direct group pairs/unresolved legacy shares. Received/Paid count only settled payment ledger entries with explicit parties, deduplicated IDs, filtered by recorded payment dates (submission date; no confirmation timestamp available). Disclose excluded unattributed legacy entries. Filters do not alter current obligations/reminders.

Profile keeps working receiving, security, friendship/group, notifications, appearance, sync, privacy and support/version actions. Remove static language/currency rows and duplicated provider advertising. Detail retains one actionable balance/party summary and ledger history; omit its duplicate KPI/mascot/progress strip. No stored history/identity/recipient-confirmation behavior changes.

Appearance choices are padded16px rounded Material/ListTile surfaces with selected warm fill, strong outline and radio/check state; no flush rectangular highlight. Keep safe insets/scrollable200% text, busy/error and acknowledged saved-state behavior. Narrow/large-text Profile places Edit below identity. Selected fills must paint on the nearest Material rather than be hidden by an opaque decoration. [Plan](../plans/minimal-daily-debts-home.md) / [QA-028](../progress/tasks/QA-028.md).


2026-11-17T09:40:07.033Z — [QA-028 verification](../verification/VER-QA-028-DAILY-HOME.md): minimal Home and rounded mode choices now installed on private normal15. Prior duplicate Home/detail/static-settings descriptions remain historical; DEC-015 governs current hierarchy.

## Visible feedback and lower-right Add ? 2026-11-17T10:06:37.311Z

Supersedes prior dock Add placement under the latest user direction. Home/My Tabs expose one lower-right floating Add tab action above three equal Home/My Tabs/Profile slots. Hide it on Profile/detail, retain its real creation handler and leave bottom scroll clearance. Use shared showTabbyBottomSheet/TabbyFeedback for bottom-sheet feedback; validation, picker/retry and realtime notices stay visible on the current sheet rather than on a covered page. Nested forms own their messages; successful closing forms return messages to their current parent/page. Existing inline errors and session/draft guards remain. Add content/progress/actions must scroll/wrap with the keyboard and200% text. [QA-029](../progress/tasks/QA-029.md) / [plan](../plans/ui-feedback-audit.md).

2026-11-17T10:17:39.198Z ? Feedback routing also excludes inactive StatefulShell branches: mounted/local-current alone does not prove visible. Use route plus TickerMode visibility in the same messenger; test actual hit targets.

2026-11-17T10:27:13.541Z - QA-029 current UI and active-sheet feedback are installed in private normal16; [verification](../verification/VER-QA-029-VISIBLE-FEEDBACK.md). Earlier dock-Add descriptions are historical.

## Full-screen forms and compact edge-to-edge sheets - 2026-11-17T13:24:15.294Z

User approved full-screen Add/edit pages and explicitly requires compact sheets to span right to left. Add Tab, payment entry, profile editing, receiving-method editing and group creation use an opaque full-screen Material route with safe areas, pinned leading Back/header, scrollable fields and existing draft/session/back/save guards. Add's Back retains its step behavior. Quick choices/settings/information remain compact in height with rounded top corners and full viewport width, including tablets/rotation; remove the former560px cap. Internal padding stays comfortable. Preserve scoped visible feedback and keyboard/200% reachability. [Plan](../plans/fullscreen-forms-and-edge-sheets.md) / [QA-030](../progress/tasks/QA-030.md).

2026-11-17T13:38:38.754Z - DEC-016 form/sheet presentation installed in private normal18 with full837/native5 and actual full-width/viewport geometry evidence; [QA-030 verification](../verification/VER-QA-030-FORM-PRESENTATION.md).

## Situation mascots - 2026-11-17T14:30:25.234Z

User-supplied thinking/waiting/helpful/reminder/celebrating originals are approved and rendered by shared UI-only TabbyMascotPose with existing welcome/notebook/neutral/sleeping. Use restrained whole-body breath/sway/tilt and a finite success hop; idle retains actual eight-frame blinking. No independent paw/eye/tail motion is implied by single PNG poses. Render normalized transparent bounds at stable bottom-center anchor and bounded display resolution. Pause while hidden/covered/backgrounded; system/app reduced motion shows an immediate untransformed still. Pending payments remain waiting and only confirmed status can celebrate financially. Add success uses art-only celebration without settled claims. Home/welcome/loading/error/reminder states use one mascot with native labels, no clutter. [Artwork](../assets/situation-mascot-artwork.md) / [QA-031](../progress/tasks/QA-031.md).

2026-11-17T14:37:16.091Z - Situation art and lifecycle-aware motion installed in private normal1.0.4+19. Full853/native6 and six synthetic light/dark previews pass; source, artifact and tablet startup documented in [QA-031 evidence](../verification/VER-QA-031-SITUATION-MASCOTS.md). No extra art is required for these whole-body effects.

2026-11-17T19:07:11.599Z - [QA-033](../progress/tasks/QA-033.md) supersedes prior single-pose-only situation motion: five sibling sheets provide real blinks/tail/paw frames with fixed registration, quiet holds and original still fallback. Thinking/waiting retain calm paw poses; helpful/reminder gesture briefly; success gestures finish once without replay. Original neutral blink and welcome/notebook body motion remain. Private normal21 installed with full890/native6 acceptance; no new financial meaning.

## Landing screen previews - 2026-11-19T09:40:06+08:00

The Screens section uses visitor-controlled Home, Tab details and Dark mode options. The selected Tabby screenshot and caption appear in a stable preview with a brief crossfade. The options work with a keyboard and reduced motion switches directly. Without JavaScript, all three screenshots and captions remain readable. [WEB-003](../progress/tasks/WEB-003.md), [Feature tabs reference](https://brewedops.cloud/motionlibrary/?id=cards-feature-tabs).

## Screens carousel restoration - 2026-11-19T10:03:39+08:00

The owner restored the six-screen carousel in A look inside. The Home, welcome and tab-detail screenshots appear in light and dark. Reduced-motion visitors can scroll the single static row. This supersedes the WEB-003 tabs for that section. [WEB-005](../progress/tasks/WEB-005.md).
