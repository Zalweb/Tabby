# Situation mascot animation implementation plan

2026-11-17T14:04:57.426Z. User approved the reviewed five supplied transparent poses and asks to implement their animations now. Existing welcome/notebook/blink/sleeping assets remain. No additional image is needed for whole-body motion; eye/paw/tail articulation needs separate matching frames/layers and is outside this supplied set. Use existing Flutter controllers/painters, with no runtime image generation or new dependency.

## Design and shared interface

UI-only TabbyMascotPose selects neutral, welcome, notebook, thinking, waiting, reminder, celebrating, helpful, sleeping. Keep domain MascotEmotion unchanged; the shared widget maps its9 financial states into those poses, with an explicit presentation override for error/welcome. Copy original5 PNGs without modification into assets/branding/mascot/, record hashes/dimensions/crop bounds and render normalized transparent bounds at a common bottom-center anchor. Existing idle/sleep frame art continues to blink/rest. Decode new artwork at bounded display resolution and contain repaints.

Preserve existing bubbles/status/tap callbacks. Art-only constructor has no bubble/ring/badge so welcomes/Home/success stay minimal. One shared motion controller handles soft breaths/thinking nod/patient sway/reminder tilt and short celebration hops. Celebration is finite, not endless; reduced-motion renders untransformed art immediately. Suspend all timers/controllers offstage, beneath covered routes and when backgrounded, then resume loops without replaying celebrations. System reduced-motion always wins over app preference.

Connect art to existing real states: welcome/onboarding, Google loading/browser wait/error, notebook Home summary, Add success, reminders/empty states, pending payments and receiving-method load/retry; use helpful for404 and sync failure/offline if relevant existing UI admits a small illustration. Keep validation inline and no mascot in every field/snackbar. Never use celebration for pending/rejected payments or infer payment confirmation from a receipt. No ledger/auth/provider/schema or routing contract changes.

## Steps

- [x] Claim QA-031/read set and source reservations, preserve all current dirty work/custom-debt specification.
- [x] Copy exact supplied art, generate provenance/bounds and write pose/animation/lifecycle/reduced-motion/one-shot regression tests.
- [x] Implement shared art/engine plus restrained real-state bindings. Preserve existing layout/back/session semantics and truthful payment labels.
- [x] Run focused/full tests and analysis; render/inspect synthetic pose/state light/dark previews and retain existing large-text form coverage. Extend native entry contract to6 cases for production image loading/motion on tablet.
- [x] Verify current device/build reservation, package same-key universal19+ after baseline check, inspect artifact/source/installed bytes and preserve login/data/.usbtest.
- [x] Update design/skill/provenance/task/evidence, project-memory refresh/plain/base checks. Leave independent review/iOS/unexercised live backend gates explicit.

## Review focus

Asset changes must not jump or crop ears/paws; no active tick/frame after hidden/background/reduced motion; pose changes still display correct art under async image load; repeated parent rebuilds must not replay success; pending remains waiting. Tests pin the actual pose/transform/painter asset and timer behavior rather than only finding friendly text.

2026-11-17T14:37:16.091Z - Executed in private normal19; full853/native6, immutable source and installed-byte/startup proof in [QA-031 evidence](../verification/VER-QA-031-SITUATION-MASCOTS.md). Independent integration review and listed platform gates remain unverified; checked execution steps do not assert final release approval.
