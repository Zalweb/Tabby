# Articulated mascot frames implementation plan

2026-11-17T18:42:00+00:00. User confirms adding paw waving, tail movement and blinking to the new situation poses and asks implementation now. Follow [QA-033](../progress/tasks/QA-033.md). Existing single-pose originals stay unchanged as reduced-motion/loading fallback; generated sibling sprite sheets provide actual articulation. No change to emotion/payment meaning.

## Design and approach

Generate matching frames using each exact transparent original as identity/pose reference. Prefer compact uniformly spaced frame sheets over a new vector rig or cut-apart layers: existing art is raster and the app already has an image painter. Inspect consistency and alpha before enabling any sheet. Use fixed common frame windows/anchor, not independent tight-fit scaling per frame, to avoid breathing size jitter. New frames show subtle eye closure and tail movement; reminder/helpful can wave their raised/free paw. Thinking and waiting stay calm; celebration remains a finite success event. No new package or icon decoration. Original neutral blink remains untouched.

The renderer selects a short blink/tail/wave clip separated by long still holds. No perpetual waving. Reuse current route/TickerMode/background/app-system reduced-motion gating, reset to static original for reduced motion, and stop all timers while hidden. Existing finite celebration must not turn into an endless gesture or replay on rebuild/resume. Missing/corrupt sheet falls back to original pose. Decode sheets at a bounded per-cell display resolution.

## Execution

- [x] Generate transparent sibling sheets from five approved originals with built-in image generation; preserve originals, persist prompts and provenance.
- [x] Inspect real generated frames for identity, alpha, grid/window registration and clipping; reject unsuitable variants.
- [x] Add UI-only atlas metadata and sparse playback; preserve public pose API, semantic labels, financial states and still fallback.
- [x] Verify actual frame loading/change, clip ordering, pause/resume, reduced motion, missing-art fallback and finite celebration; run relevant tests and analysis.
- [x] Render and inspect animated synthetic previews. Coordinate build/device ownership and use a new private version only after source/artifact checks and reservation release; do not ship unverified concurrent source.
- [x] Update task/design/skill/evidence and memory refresh/plain/base validation, with unverified gates explicit.

2026-11-17T19:07:11.599Z - Execution delivered in private normal21; [evidence](../verification/VER-QA-033-ARTICULATED-MASCOTS.md). Independent review/platform gates remain open.
