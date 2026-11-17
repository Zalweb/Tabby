# Consistent warm Tabby UI design and implementation plan

Date: 2026-11-17. User direction: extend the existing login/introduction design through Home and every page, update design docs, and create a reusable design skill. This is the selected visual direction; no new visual concept or authentication behavior is requested.

## Design

Use one shared warm palette: cream canvas #FFFAF2, warm-white cards #FFFFFF, charcoal ink #292321, muted brown #6B6058, amber action #FFB342, soft cream highlight #FFF0D8 and warm border #E7D8C5. Dark mode follows the existing introduction: canvas #181A19, charcoal raised surfaces, warm-white ink and the same amber. Primary amber controls always use charcoal text. Readable burnt-brown links and focus borders replace blue/green brand accents. Keep actual confirmation/error states semantically distinct and labeled; ordinary debt is not an error.

Headers use the same canvas as content, with a restrained cream/amber hero treatment on Home; avoid solid green/teal page backgrounds. Cards, sheets, dialogs, navigation, inputs, selectors, loading, empty states and overlays inherit shared tokens. Warm input fills, 16px controls, 20–24px cards and clear typography match introduction simplicity. Use actual existing Tabby art at meaningful welcome/empty states; do not add decorative icon clusters or new generated imagery. QR and receipt/image pixels, provider marks and user avatars retain their actual colors. Main ledger pages stay information-first and scrollable at200% text.

Approaches: changing only the theme leaves explicit headers and component colors inconsistent; manually inventing each page palette repeats the problem. Use central semantic tokens plus a screen/widget audit. Retain temporary legacy color aliases only for compatibility, with canonical warm names in application code. This implementation choice follows the user's existing design and authorization.

Keep all money, persistence, authentication, routing, notification, account/session and recipient-confirmation behavior. No backend deployment, new dependencies or database changes. Preserve pre-existing/concurrent working-tree edits. The existing launcher art is not part of this color migration. Private tablet upgrade follows the existing session authorization after tests/build checks; do not sign out or clear owner data.

## Implementation

- [x] Record branch/base/read set and file reservations under QA-026; snapshot current source before editing.
- [x] Consolidate TabbyColors, TabbyPalette and TabbyTheme; make welcome colors consume the shared palette.
- [x] Audit all UI surfaces: startup/lock/auth, Home/nav, tabs/groups/details/forms, connections/profile/settings/privacy, payments/QR, notifications and reusable widgets. Replace leftover mint/blue/teal decorative colors and fix light/dark foreground contrast.
- [x] Add meaningful palette/contrast and representative screen/sheet regressions; inspect production-widget previews across light/dark and small/tablet/large text. Run full regression and analysis.
- [x] Update DESIGN with current authority, append superseding DEC-014 and area-plan checkpoint, index the reusable repository skill; install the same skill in the user's default Codex skill directory and validate it.
- [x] Record exact verification and remaining environments, refresh/check repository memory and base coverage; if ADB remains available build/verify/install the private signed update in place with artifact/source identity checks.

## Skill

Create tabby-design, scoped to building/reviewing this app's warm mascot-first Flutter interface. Include concrete palette roles, native implementation references, semantic finance/QR exceptions, low icon density, light/dark/accessibility checks and the authoritative design-doc path. Keep it useful for a later agent without encoding current test counts or granting deployment permission. Store a versioned repository source and a discoverable user-level copy.


2026-11-17T08:50:16.794Z — Implementation/check sequence executed; [terminal evidence and unverified gates](../verification/VER-QA-026-WARM-UI.md). Base coverage failures outside this task are recorded rather than hidden by broadening ownership.
