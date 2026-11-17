# Articulated situation mascot artwork

2026-11-17T19:00:00+00:00. User explicitly confirms real paw/tail/eye animation after [QA-031](../progress/tasks/QA-031.md). Built-in image_gen produced five transparent sibling sheets using each approved original as the edit/identity reference. [Exact prompts](articulated-mascot-prompts.json), [generated PNG provenance and measured windows](../../assets/branding/mascot/frame-manifest.json), [plan](../plans/articulated-mascot-frames.md), [task](../progress/tasks/QA-033.md). Original images remain byte-for-byte unchanged.

| Sheet | Frames | Clips |
|---|---:|---|
| tabby-thinking-frames-v1.png | 8 | Blink, restrained tail swish; chin paw stays thoughtful |
| tabby-waiting-frames-v1.png | 8 | Blink, restrained tail swish; paws remain patient |
| tabby-helpful-frames-v1.png | 12 | Blink, tail swish, small extended-paw gesture |
| tabby-reminder-frames-v1.png | 12 | Blink, tail swish, raised-paw wave |
| tabby-celebrating-frames-v1.png | 12 | Happy eye opening/closure and raised-paw cheer; finite clip |

The sheets contain actual different eye/tail/paw drawings, not just transformed single-pose images. Runtime source windows have a common width/height within each sheet. Measured ear-color centroid and lowest paw anchor compensate small generated placement differences without editing pixels or independently scaling each frame. Non-integral generated grid dimensions are split at rounded cell boundaries, then actual alpha extents are checked; every frame has transparent padding and no clipping. Small generative drawing differences remain; the character proportions/stripes/ears/pads/outline were visually inspected, not claimed pixel-identical to originals.

One timer advances a short clip only after quiet holds. Reduced motion or a missing/failed sheet uses the exact approved still. Hidden/background routes cancel timers; success completes once and interrupted success never replays. No new dependency, financial state, provider callback or launcher-icon change. Existing neutral blink and welcome/notebook body motion stay intact.
